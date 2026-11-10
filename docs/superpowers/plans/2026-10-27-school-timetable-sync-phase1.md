# School Timetable Sync — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show students the school's own timetable (an xlsx in the school's Google Drive) as dated per-class lessons, synced every day at 08:00 and 17:00 JST, with a push to each class whose lessons changed.

**Architecture:** One member of the school's Google Workspace domain links the file once from a web page. The page uses OAuth `drive.file` scope plus Google Picker, and the server stores that member's refresh token. A scheduled Cloud Function then:
1. downloads the file,
2. parses it into `school_days` docs (one per class per date),
3. diffs the new docs against the stored ones,
4. sends FCM pushes.

The Flutter app detects the school from the verified email domain and shows these docs alongside the student's personal classes.

**Tech Stack:** Firebase Functions v2 (Node 22, ESM, region `asia-northeast1`), `exceljs`, `node:test`, Firestore rules, Flutter + Riverpod, Google Identity Services, and Google Picker (in a static HTML page).

**Spec:** `docs/design/school_timetable_sync_design_ja.md`. This plan covers §4–§8, §10–§12 and §14 for 第1段階 only. 教員入力 (§9, 第2段階) is out of scope.

## Global Constraints

- **Region and runtime:** every new function uses `region: 'asia-northeast1'`, the same as the existing functions in `functions/index.js`.
- **Sync schedule:** `0 8,17 * * *`, `timeZone: 'Asia/Tokyo'`.
- **OAuth scopes:** `https://www.googleapis.com/auth/drive.file` (non-sensitive) plus `openid email`. **Never** request `drive.readonly`.
- **Domain check:** the domain is read from the **verified** email. Firestore rules check `request.auth.token.email_verified == true`. On link, the server additionally requires the Google id_token `hd` claim to equal the domain.
- **Secret storage:** `school_secrets/{domain}` has no client access at all. Do not add a rules match for it; the implicit deny is the protection.
- **Privacy (fixtures):** test fixtures use made-up teacher names (田中, 鈴木, 佐藤). Never commit the real school file or its cell contents.
- **Privacy (AI):** teacher names never go into AI payloads (existing rule in `CLAUDE.md`).
- **UI text:** all user-visible strings are Japanese and go through `AppStrings.t()`. Every new key is added to all 21 `assets/l10n/*.json` files. Write them with `json.dump(..., ensure_ascii=False, indent=2, sort_keys=True)` plus a trailing newline, and keep `test/core/l10n_parity_test.dart` green.
- **Code comments:** match the existing files: English, sparse.
- **Platforms (spec §11.1):** push and reminders on Android/iOS only. Web gets the in-app 「最近の変更」 feed and a week grid at width ≥ 600. Desktop = the web build (PWA); no native Linux/Windows work.
- **No commits or deploys** unless the user asks. The user runs `firebase deploy` themselves.
- **Final checks:**
  - `flutter analyze` must be at **0 issues**.
  - `flutter test` must pass.
  - `cd functions && npm run lint && npm test` must pass.

## Review Focus

1. **Notifications for school changes respect the existing switch.** A student who turned notifications off in Settings gets no school-change push. This already works today, because turning the switch off deletes `fcmToken`. Pinned by the Task 3 test `notifySchoolChanges skips users without fcmToken`.
2. **A malformed or re-formatted xlsx never wipes data or spams.** Expected: an error status is recorded, previous days are kept, and no student push goes out. Pinned by the Task 3 test `syncSchool keeps previous days and records error on parse failure`.
3. **Edits to past weeks never notify.** Pinned by the Task 2 test `diffDays ignores dates before today`.
4. **A gmail.com or other non-Workspace account cannot link or read a school.** Pinned by the Task 3 test `linkSchoolStart rejects tokens without matching hd`, plus the Task 4 rules checks.
5. **A user whose email is unverified (email/password signup) sees no school data and no errors.** Expected: the app falls back to the current manual mode. Pinned by the Task 6 test `domainOf returns null for unverified email`.

---

### Task 1: xlsx → rows → parsed timetable (pure parser)

**Files:**
- Create: `functions/school/timetable_xlsx.js`
- Create: `functions/test/fixtures/school_rows.json` (synthetic; layout described below)
- Create: `functions/test/timetable_xlsx.test.js`
- Modify: `functions/package.json`:
  - add dependency `"exceljs": "^4.4.0"`;
  - add script `"test": "node --test"`.

**Interfaces:**
- Produces:
  - `xlsxToRows(buffer: Buffer): Promise<string[][]>`. Reads the first worksheet. Each cell becomes a string; merged and empty cells become `''`. Row and column order are kept, and the array is 0-indexed.
  - `parseTimetableRows(rows: string[][]): ParsedTimetable`. Throws `TimetableParseError` (exported `class TimetableParseError extends Error`) when the rows cannot be parsed.
  - `ParsedTimetable = { periods: Period[], grades: number[], courses: string[], days: Day[] }`
  - `Period = { key: '1-2', label: '1・2限', start: '09:00', end: '10:30' }`
  - `Day = { grade: number, course: string, date: 'YYYY-MM-DD', slots: Slot[] }`
  - `Slot = { period: string /* Period.key */, subject: string, teacher: string, room: string, note: string, status: 'normal'|'cancelled'|'event'|'tbd'|'elective' }`
  - `dayDocId(domain, day) => \`${domain}_${day.grade}_${day.course}_${day.date.replaceAll('-', '')}\``

**Fixture layout:**
- It mirrors the real file. Column A is empty. In each week block:
  - a row with `N年生` at the left of each half;
  - a row with dates (`10月26日` …) in five consecutive columns per half;
  - four period sections whose label cell sits two columns left of the first date column, e.g. `１・２限目 09：00～10：30`;
  - a `休憩` row.
- Each period section has, per half:
  - a course row: course name one column left of the first date column, subjects in the five date columns;
  - then a teacher row: `担当【教室】` cells, with an empty course cell.
- The fixture has two weeks (one in October, one in January) and two grades (1年生 left half, 2年生 right half), with courses 農業 and 観光.
- Add a `2026年度 後期` title cell in row 0.

**Algorithm:** the steps below are the one non-obvious part; the rest is plain code.
1. Normalize every cell with `s.normalize('NFKC').replace(/\s+/g, ' ').trim()`. NFKC turns `１・２限目 09：00～10：30` into `1・2限目 09:00~10:30`.
2. **Fiscal year:** take the first cell matching `/(\d{4})年度/`. Months 4–12 get that year; months 1–3 get year + 1. If no cell matches, throw.
3. **Date runs:** a date row is any row with at least 3 cells matching `/^(\d{1,2})月(\d{1,2})日$/`. Within a date row, each maximal run of consecutive date columns is one *week-half*. The run's grade is the closest `/^(\d)年生$/` cell at a column ≤ the run start. Look in the same row first, then up to 2 rows above.
4. For each week-half, walk the rows below the date row until the next date row or the next `年生` header row.
   - **Period header:** if `row[start-2]` matches `/(\d)・(\d)限目? ?(\d{1,2}):(\d{2}) ?[~-] ?(\d{1,2}):(\d{2})/`, it sets the current period:
     - key `a-b`;
     - label `a・b限`;
     - start and end times zero-padded to `HH:MM`.
   - **Course row:** `row[start-1]` is non-empty, is not `休憩`, and does not match `年生`. The subjects are `row[start..start+4]`. If the next row's `[start-1]` is empty, the teachers are `nextRow[start..start+4]`; otherwise use `''`.
5. Slot per day column, given `subj` and `tcell`:
   - **No slot:** both are empty.
   - **Teacher cell:** parse `tcell` with `/^(.*?)【(.*?)】(.*)$/` into teacher, room and rest. If there is no `【`, use teacher `''`, room `''`, rest = `tcell`. `note` = rest (trimmed).
   - **Status, first match wins:**
     - `cancelled`: `/休講/` matches either cell, or `subj === '休み'`;
     - `event`: `/学園祭準備|学園準備|宿泊研修|全員登校日|企業説明会|郊外学習/` matches either cell;
     - `tbd`: `/追って連絡/` matches either cell;
     - `elective`: `subj` is `X`, `Y` or `Z`;
     - otherwise `normal`.
   - When the status came from a word in `tcell` that is not the teacher pattern (e.g. `英語休講`), that word ends up in `note`.
6. Emit one `Day` per (grade, course, date) seen, **including days with zero slots**, so a fully removed day is diffable.
7. **Validation, throwing `TimetableParseError`:**
   - no week-half found;
   - any week-half without exactly 4 periods;
   - a date that `new Date()` rejects;
   - two different time ranges for the same period key.

- [ ] **Step 1: Write the failing tests** in `functions/test/timetable_xlsx.test.js` (`node:test` + `node:assert/strict`):
  - `parses periods from headers`:
    - `periods` deep-equals the four keys `1-2`, `3-4`, `5-6`, `7-8`;
    - times are 09:00–10:30, 10:40–12:10, 13:10–14:40 and 14:50–16:20.
  - `assigns grade and course per half`:
    - `grades` = `[1, 2]`;
    - `courses` = `['農業', '観光']`;
    - the 1年 農業 Monday in October has slot `{period:'1-2', subject:'IT概論2', teacher:'田中', room:'104', note:'', status:'normal'}`.
  - `rolls January into next year`: the January week's dates start with `2027-01-`.
  - `classifies statuses`: the fixture cells `英語休講`, `学園祭準備`, `時間は追って連絡`, `X` and `田中【101】企業説明会` give `cancelled`, `event`, `tbd`, `elective` and `event`, with note `企業説明会`.
  - `emits empty days`: a fixture day with no lessons for 2年 観光 exists with `slots: []`.
  - `throws on missing periods`: removing one period header row → `TimetableParseError`.
  - `xlsxToRows round-trips exceljs workbook`: build a workbook in memory with exceljs from `school_rows.json`, call `writeBuffer()`, then `xlsxToRows`. The result deep-equals the fixture rows, compared with trailing empty cells trimmed per row.
- [ ] **Step 2:** Run `cd functions && npm install && npm test`. Expected: FAIL, module not found.
- [ ] **Step 3:** Implement `xlsxToRows`, `parseTimetableRows`, `dayDocId` and `TimetableParseError` in `functions/school/timetable_xlsx.js`, following the algorithm above.
- [ ] **Step 4:** Run `npm test && npm run lint`. Expected: all tests PASS and lint is clean.

---

### Task 2: diff and push text

**Files:**
- Create: `functions/school/diff.js`
- Create: `functions/test/diff.test.js`

**Interfaces:**
- Consumes: `Day` and `Slot` from Task 1.
- Produces:
  - `slotsHash(slots: Slot[]): string`. sha1 hex of `JSON.stringify` over slots sorted by `period`.
  - `diffDays(prev: Map<string /*date*/, Slot[]>, next: Day[] /* one class */, todayIso: string): Change[]`
  - `Change = { date, period, before: Slot|null, after: Slot|null }`. A change is emitted when any of subject, teacher, room, note or status differs, or when a slot was added or removed. Only dates with `date >= todayIso` are included.
  - `describeChange(change: Change, periods: Period[]): { date, period, subject, what }`. `what` follows the rules below; `buildClassMessage` uses it.
  - `buildClassMessage(grade, course, changes: Change[], periods: Period[]): { title: string, body: string }`

**Message format** (exact copy from spec §8):
- **Title:** `時間割の変更`.
- **Body:** `${grade}年・${course}：${M}/${D}（${曜}）${label} ${subject} → ${what}`, plus ` ほか${n-1}件` when n > 1. The message describes the earliest change (by date, then period).
  - `曜` is one of `日月火水木金土`.
  - `subject` is `after?.subject || before?.subject`.
  - `what` is:
    - `休講` when `after.status === 'cancelled'`;
    - `教室 ${before.room}→${after.room}` when only the room changed;
    - `授業なし` when `after` is null;
    - `追加` when `before` is null;
    - otherwise `変更`.

- [ ] **Step 1: Write the failing tests:**
  - `diffDays ignores dates before today`;
  - `diffDays detects room change`;
  - `diffDays detects removed and added slots`;
  - `diffDays returns [] for identical days`;
  - `buildClassMessage formats cancellation`. Expected exactly `1年・農業：10/29（木）3・4限 英語 → 休講 ほか1件` for two changes on 2026-10-29 period `3-4` (subject 英語, after.status cancelled) plus one more.
  - `buildClassMessage formats room change`. Expected `… 教室 101→203`.
- [ ] **Step 2:** Run `npm test`. Expected: FAIL.
- [ ] **Step 3:** Implement the functions in `functions/school/diff.js`.
- [ ] **Step 4:** Run `npm test && npm run lint`. Expected: PASS.

---

### Task 3: Google token and Drive helpers, sync orchestrator, Cloud Functions

**Files:**
- Create: `functions/school/google.js`
- Create: `functions/school/sync.js`
- Create: `functions/test/sync.test.js`
- Modify: `functions/index.js` (exports only; logic stays in `school/`)

**Interfaces:**
- Consumes: Task 1 (`xlsxToRows`, `parseTimetableRows`, `dayDocId`, `TimetableParseError`) and Task 2 (`diffDays`, `slotsHash`, `buildClassMessage`).
- Produces, in `school/google.js`. All use global `fetch` (no new dependency) and throw `Error` with the HTTP status on a non-2xx response.
  - `exchangeCode(code, {clientId, clientSecret}) → { refreshToken, accessToken, email, hd }`.
    - POST to `https://oauth2.googleapis.com/token` with `grant_type=authorization_code` and `redirect_uri=postmessage`.
    - `email` and `hd` are decoded from the id_token payload, which is trusted because it came from the token endpoint over TLS.
  - `refreshAccessToken(refreshToken, {clientId, clientSecret}) → accessToken`.
  - `getFileMeta(accessToken, fileId) → { id, name, mimeType, modifiedTime }`. Uses `GET https://www.googleapis.com/drive/v3/files/{id}?fields=id,name,mimeType,modifiedTime&supportsAllDrives=true`.
  - `downloadXlsx(accessToken, meta) → Buffer`.
    - If `meta.mimeType === 'application/vnd.google-apps.spreadsheet'`: use `/export?mimeType=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.
    - Otherwise: use `?alt=media&supportsAllDrives=true`.
- Produces, in `school/sync.js`. Dependencies are injected so tests run with fakes and no network:
  - `syncSchool(domain, {force, notify}, deps) → { status: 'ok'|'skipped'|'error', weeks, classes, changes }`
  - `deps = { db, google /* the 4 functions above, pre-bound with client creds */, sendMulticast, now: () => Date }`
- Produces, in `index.js`:
  - `linkSchoolStart` (onCall, secret `GOOGLE_OAUTH_CLIENT_SECRET`, string param `GOOGLE_OAUTH_CLIENT_ID`):
    - input `{code}`; returns `{accessToken}`.
    - The caller's Firebase token email must be verified, `exchangeCode().email` must equal it, and `hd` must equal its domain. Otherwise throw `permission-denied`.
    - If `schools/{domain}` exists and the caller is not in `admins`: `permission-denied`.
    - Writes `school_secrets/{domain} = {refreshToken, linkedBy: uid, linkedEmail, linkedAt}`.
    - Merges into `schools/{domain}`: `admins` arrayUnion uid.
  - `linkSchoolFile` (onCall, same secret and param):
    - input `{fileId, schoolName}` (`schoolName` 1–100 chars); caller must be an admin.
    - Saves `schools/{domain}.name` and `.file = {id}`, then runs `syncSchool(domain, {force: true, notify: false})`.
    - Returns `{weeks, classes, periods}`, or throws `failed-precondition` with the parse error message.
  - `syncSchoolNow` (onCall, admin only): runs `syncSchool(domain, {force: true, notify: true})`.
  - `syncSchoolTimetables` (`onSchedule({schedule: '0 8,17 * * *', timeZone: 'Asia/Tokyo', region: 'asia-northeast1', secrets: [...]})`, from `firebase-functions/v2/scheduler`): for every `schools` doc with `file.id`, runs `syncSchool(domain, {force: false, notify: true})` sequentially. Each school is wrapped in try/catch so one failure does not stop the rest.

**`syncSchool` behavior:**
1. Load `school_secrets/{domain}` and `schools/{domain}`, then get an access token and `getFileMeta`.
2. If `!force && meta.modifiedTime === school.file.modifiedTime`, return `skipped` and only update `sync.lastRunAt`.
3. Download, run `xlsxToRows`, then `parseTimetableRows`.
4. **On `TimetableParseError` or any download error:**
   - set `schools.sync = {status: 'error', error: message (≤300 chars), lastRunAt}`;
   - leave all `school_days` untouched and send no student push;
   - if the previous `sync.status !== 'error'`, push once to the first admin's `fcmToken`: title `時間割の取り込みに失敗しました`, body = message.
   - return `error`.
5. For each (grade, course), read the existing day docs by id. Then diff with `todayIso` = today in Asia/Tokyo (`Intl.DateTimeFormat('sv-SE', {timeZone: 'Asia/Tokyo'})`).
6. Write the changed or new day docs in batches of ≤450: `{domain, grade, course, date, slots, hash, updatedAt}`. Write only when the hash differs.
6b. For each class with changes, write `school_changes/{domain}_{grade}_{course}` = `{items}`: the new `describeChange` results plus `at` (server time), prepended to the existing items and capped at 30. Skip this on the first link run (`force && !notify`).
7. Update `schools/{domain}`:
   - `periods`, `grades`, `courses`;
   - `file.name`, `file.modifiedTime`;
   - `sync = {status: 'ok', error: null, lastRunAt}`.
8. If `notify`: for each class with changes, query `users` where `schoolDomain == domain`, `grade == String(grade)`, `course == course`. Collect `fcmToken`s and send one `sendEachForMulticast` with `buildClassMessage` and `android: {notification: {channelId: 'eduplanner_reminders'}}`. Users without a token are skipped.

- [ ] **Step 1: Write the failing tests** in `functions/test/sync.test.js`. Use a tiny in-memory fake of the Firestore API that `syncSchool` uses (`collection().doc().get/set`, `getAll`, `where().where().where().get`, `batch`), plus fake `google` and `sendMulticast`.
  - `syncSchool writes days and sends one push per changed class`. Also asserts that the `school_changes` doc has the new item first and at most 30 items;
  - `syncSchool skips when modifiedTime unchanged`;
  - `syncSchool keeps previous days and records error on parse failure`. Asserts: day docs unchanged, `sync.status === 'error'`, zero student pushes, one admin push. On a second failing run there is no admin push.
  - `notifySchoolChanges skips users without fcmToken`;
  - `linkSchoolStart rejects tokens without matching hd`. Test the extracted pure check `assertLinkAllowed({callerEmail, callerVerified, tokenEmail, hd, school, uid})` exported from `sync.js`. It throws for:
    - missing `hd`;
    - `hd` ≠ caller domain;
    - unverified caller;
    - a non-admin when a school exists.
- [ ] **Step 2:** Run `npm test`. Expected: FAIL.
- [ ] **Step 3:** Implement `google.js`, `sync.js` (including `assertLinkAllowed`) and the four exports in `index.js`. Reuse the existing `requireAuth`, `db()` and `messaging()` helpers in `index.js`.
- [ ] **Step 4:** Run `npm test && npm run lint && node --check index.js`. Expected: PASS.

---

### Task 4: Firestore rules and the `users.schoolDomain` field

**Files:**
- Modify: `firestore.rules`

**Interfaces:**
- Produces:
  - the helper `function inDomain(d) { return isAuth() && request.auth.token.email_verified == true && request.auth.token.email.split('@')[1] == d; }`;
  - `match /schools/{domain} { allow get: if inDomain(domain); }`;
  - `match /school_days/{dayId} { allow get: if inDomain(dayId.split('_')[0]); }`. The rule is id-based so that `get` on a missing day is allowed: the app listens to all 5 weekdays.
  - `match /school_changes/{feedId} { allow get: if inDomain(feedId.split('_')[0]); }`.
  - In the `users/{userId}` write rule: `&& (!('schoolDomain' in request.resource.data) || request.resource.data.schoolDomain == null || request.resource.data.schoolDomain == request.auth.token.email.split('@')[1])`.
  - No `list` and no `write` on the new collections, and no rule at all for `school_secrets`.

- [ ] **Step 1:** Edit the rules as above.
- [ ] **Step 2:** Verify with the emulator. Run `firebase emulators:start --only auth,firestore` and seed through REST with `Authorization: Bearer owner`, as in earlier sessions. Check that:
  1. a verified `a@school.test` user can `get` `schools/school.test` and `school_days/school.test_1_農業_20261026`, including one that does not exist;
  2. a verified `b@other.test` user gets 403 on both;
  3. an unverified `a@school.test` user gets 403;
  4. any user gets 403 on `school_secrets/school.test`;
  5. writing `users/{uid}.schoolDomain = 'other.test'` gets 403, and writing the caller's own domain succeeds.

  Record the 5 results in the task report.

---

### Task 5: Link page (static HTML on Firebase Hosting) and console setup

**Files:**
- Create: `web/school-link.html`. Flutter copies `web/` into `build/web`, so it is served at `/school-link.html`. Hosting serves existing files before the `**` rewrite.

**Interfaces:**
- Consumes: `linkSchoolStart` and `linkSchoolFile` (Task 3).
- **The page** is plain HTML and JS. Japanese UI, no framework. It loads:
  - Firebase JS SDK compat 12.x (app, auth, functions) from `https://www.gstatic.com/firebasejs/`;
  - GIS `https://accounts.google.com/gsi/client`;
  - `https://apis.google.com/js/api.js` for Picker.
- **Config:** web Firebase config copied from `lib/firebase_options.dart` (`web`), plus three constants at the top of the script:
  - `OAUTH_CLIENT_ID`;
  - `PICKER_API_KEY`;
  - `GCP_PROJECT_NUMBER`.
- **Flow:**
  1. 「学校のGoogleアカウントでログイン」 → Firebase `signInWithPopup(GoogleAuthProvider)`.
  2. 「時間割ファイルを選ぶ」 → `google.accounts.oauth2.initCodeClient({client_id, scope: 'https://www.googleapis.com/auth/drive.file openid email', ux_mode: 'popup', hint: user.email})`.
  3. The code goes to `linkSchoolStart`, which returns an `accessToken`.
  4. Open `google.picker.PickerBuilder` with:
     - `DocsView(ViewId.SPREADSHEETS)` with `setIncludeFolders(true)` and `setMode(LIST)`;
     - `setOAuthToken(accessToken)`, `setDeveloperKey(PICKER_API_KEY)`, `setAppId(GCP_PROJECT_NUMBER)`;
     - `enableFeature(SUPPORT_DRIVES)`.
  5. On pick, show a school-name input (prefilled with the domain) and 「連携する」, which calls `linkSchoolFile`.
  6. Show the result: `${weeks}週 · ${classes}クラス · コマ ${periods}`. On error, show the server message.
- **Console setup** is done by the user. List these in the task report as a checklist for the user; do not attempt them:
  1. GCP console for project `eduplannerai-97365`: enable the **Google Drive API** and **Google Picker API**.
  2. OAuth consent screen:
     - User type **External**, published "In production" (Testing-mode refresh tokens expire after 7 days);
     - scopes `drive.file`, `openid` and `email`;
     - privacy policy URL `https://eduplannerai-97365.web.app/privacy-policy.html`. Copy `docs/privacy-policy.html` to `web/privacy-policy.html` in this task.
  3. On the Firebase auto-created **Web client** OAuth ID:
     - add the authorized JS origins `https://eduplannerai-97365.web.app` and `http://localhost:8099`;
     - put its client ID into `functions/.env` as `GOOGLE_OAUTH_CLIENT_ID=…`;
     - run `firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_SECRET`.
  4. Create a browser API key restricted to the Picker API and to the HTTP referrers above, and paste it into `PICKER_API_KEY`.

- [ ] **Step 1:** Write `web/school-link.html` and `web/privacy-policy.html`.
- [ ] **Step 2:** Run `flutter build web --release`. Confirm that `build/web/school-link.html` exists. Serve it with the existing `.claude/launch.json` config `web-release` (port 8099) and load `/school-link.html`. Expected: the page renders, the console shows no errors before sign-in, and both buttons are visible (the second disabled until sign-in).

---

### Task 6: Flutter school data layer

**Files:**
- Create: `lib/features/school/models/school.dart`
- Create: `lib/features/school/school_repository.dart`
- Create: `lib/features/school/school_providers.dart`
- Modify: `lib/core/providers/app_providers.dart`: add `schoolRepositoryProvider`.
- Test: `test/features/school/school_model_test.dart`

**Interfaces:**
- Consumes: Firestore shapes from Tasks 1 and 3; `Hm` from `lib/core/constants/periods.dart`.
- Produces:
  - `enum SchoolSlotStatus { normal, cancelled, event, tbd, elective }`, with `static SchoolSlotStatus parse(String?)` (unknown → `normal`).
  - `class SchoolPeriod { final String key, label; final Hm start, end; factory SchoolPeriod.fromMap(Map) }`
  - `class SchoolSlot { final String period, subject, teacher, room, note; final SchoolSlotStatus status; factory SchoolSlot.fromMap(Map) }`
  - `class SchoolDay { final String date; final List<SchoolSlot> slots; factory SchoolDay.fromFirestore(DocumentSnapshot) }`
  - `class SchoolInfo { final String domain, name; final List<SchoolPeriod> periods; final List<int> grades; final List<String> courses; final DateTime? lastSyncAt; factory SchoolInfo.fromFirestore(DocumentSnapshot) }`. `fromFirestore` returns null-safe empty lists.
  - `SchoolRepository`:
    - `static String? domainOf(User? user)`: lowercase domain when `user != null && user.emailVerified && email` contains `@`, else null;
    - `static String dayId(String domain, int grade, String course, DateTime date)`: same format as Task 1's `dayDocId`, date as `yyyyMMdd`;
    - `Stream<SchoolInfo?> watchSchool(String domain)`: null when the doc doesn't exist;
    - `Stream<List<SchoolChange>> watchChanges({required String domain, required int grade, required String course})`: an empty list when the doc is missing. `class SchoolChange { final String date, period, subject, what; final DateTime? at; }` lives in `models/school.dart`.
    - `Stream<Map<String, SchoolDay>> watchWeek({required String domain, required int grade, required String course, required DateTime weekStart})`. It listens to 5 doc refs (Mon–Fri) and emits a map keyed `YYYY-MM-DD` that contains existing docs only. Each permission error is swallowed and the day is treated as empty.
  - `school_providers.dart`:
    - `schoolDomainProvider` (`Provider<String?>`): watches `authStateProvider` and reads `FirebaseAuth.instance.currentUser`;
    - `schoolInfoProvider` (`StreamProvider<SchoolInfo?>`): null when the domain is null;
    - `schoolClassProvider` (`Provider<({int grade, String course})?>`): from `currentUserProvider`'s `grade`/`course`. It is non-null only when `schoolInfo` exists, `grade` parses and `course` is in `schoolInfo.courses`;
    - `schoolChangesProvider` (`StreamProvider<List<SchoolChange>>`): empty when `schoolClassProvider` is null.
    - `schoolWeekProvider` (`StreamProvider.family<Map<String, SchoolDay>, DateTime>`): keyed by `weekStart`; returns an empty map when `schoolClassProvider` is null.

- [ ] **Step 1: Write the failing tests:**
  - `SchoolInfo.fromFirestore parses periods and courses`. Use `fake_cloud_firestore` if it is already in dev_dependencies; otherwise test the `fromMap` constructors directly with plain maps.
  - `SchoolSlotStatus.parse falls back to normal`.
  - `dayId matches server format`: `dayId('school.test', 1, '農業', DateTime(2026,10,26)) == 'school.test_1_農業_20261026'`.
  - `domainOf returns null for unverified email`, using a minimal fake `User` (see `test/support/fakes.dart` for existing fakes).
- [ ] **Step 2:** Run `flutter test test/features/school`. Expected: FAIL.
- [ ] **Step 3:** Implement the models, repository and providers as above.
- [ ] **Step 4:** Run `flutter test test/features/school && flutter analyze`. Expected: PASS, 0 issues.

---

### Task 7: Profile — school course choice and `schoolDomain`

**Files:**
- Modify: `lib/features/auth/screens/profile_setup_screen.dart`
- Modify: `lib/features/auth/repositories/auth_repository.dart` (`saveSchoolProfile`)
- Modify: `lib/features/auth/models/user_model.dart`: add `String? schoolDomain`, then regenerate with `flutter pub run build_runner build --delete-conflicting-outputs`.
- Modify: `assets/l10n/*.json`: add the key `school_course_from_school` = ja `学校の時間割からコースを選んでください`.

**Interfaces:**
- Consumes: `schoolInfoProvider` and `schoolDomainProvider` (Task 6).
- Produces: `saveSchoolProfile(..., String? schoolDomain)`, which writes `schoolDomain` (null clears it).

**Behavior:**
- When `schoolInfoProvider` has data with non-empty `courses`, the コース text field is replaced by `ChoiceChip`s, one per course, with the `school_course_from_school` hint. A previously saved free-text course that matches a chip is preselected.
- When `schoolInfo` has a school name and the 学校名 field is empty, prefill 学校名 with that name.
- On save, pass `schoolDomain: ref.read(schoolDomainProvider)`.

- [ ] **Step 1:** Implement the changes.
- [ ] **Step 2:** Run `flutter analyze && flutter test`. Expected: 0 issues, all pass (including `l10n_parity_test`).

---

### Task 8: Timetable screen — dated school lessons

**Files:**
- Modify: `lib/features/timetable/widgets/schedule_timeline.dart`
- Create: `lib/features/timetable/widgets/school_slot_card.dart`
- Modify: `assets/l10n/*.json`: add these keys, ja values:

  | Key | ja value |
  |---|---|
  | `school_slot_cancelled` | `休講` |
  | `school_slot_event` | `行事` |
  | `school_slot_tbd` | `未定` |
  | `school_slot_elective` | `選択科目 {label}` |
  | `school_label_personal` | `自分` |
  | `school_last_sync` | `学校の時間割 · {time} 更新` |
  | `school_recent_changes` | `最近の変更` |
  | `school_no_changes` | `変更はありません` |

- Create: `lib/features/timetable/widgets/school_week_grid.dart`
- Create: `lib/features/timetable/widgets/school_changes_list.dart`
- Modify: `lib/features/timetable/screens/timetable_screen.dart`
- Modify: `lib/features/home/screens/home_screen.dart` (banner)
- Modify: `lib/features/settings/screens/settings_screen.dart` (last sync line)
- Test: `test/features/timetable/school_slot_card_test.dart`

**Interfaces:**
- Consumes: `schoolWeekProvider(weekStart)`, `schoolInfoProvider` (Task 6), existing `ClassModel` cards.
- Produces: `SchoolSlotCard({required SchoolSlot slot, required SchoolPeriod? period})`, `SchoolWeekGrid({required DateTime weekStart})`, `SchoolChangesList({bool compact = false})`.

**Layout by width** (existing breakpoints):
- `< 600`: the timetable keeps today's day tabs + `ScheduleTimeline`. 「最近の変更」 goes on **Home** (spec §11.2-2): add a `SchoolChangesBanner` at the top of `home_screen.dart`. It shows the newest item only while some item's `at` is newer than the SharedPreferences value `school_changes_seen_at`, and tapping it opens `SchoolChangesList` in a bottom sheet and updates that value. Settings shows `school_last_sync` under the school row.
- `≥ 600` (`context.isTablet`): `SchoolWeekGrid`. Rows = `SchoolInfo.periods`; columns = 月〜金 with dates. Each cell shows the school slot (a compact `SchoolSlotCard`) and any personal class whose `kPeriodTimes` start falls inside that period's time range, marked `自分`.
- `≥ 1200` (`ScreenSize.expanded`): the grid plus `SchoolChangesList` in a 320-wide side column.
- Without school data, today's layout stays unchanged at every width.

**Behavior:**
- **Normal mode:** in `ScheduleTimeline`, when `schoolWeekProvider(weekStart)` has a `SchoolDay` for the selected date, render the school slots first, ordered by `SchoolInfo.periods` order. Then render the personal classes, each with a small `自分` label.
- **Empty state:** the empty state is shown only when both lists are empty.
- **Footer:** a footer line `school_last_sync` with `lastSyncAt` formatted as `M/d HH:mm`.
- **`SchoolSlotCard` layout:** period label and times (`09:00–10:30`), subject, `teacher · room`, and the note.
- **`SchoolSlotCard` status styling:**
  - `cancelled`: subject with `TextDecoration.lineThrough` plus the `休講` badge;
  - `event`: `行事` badge;
  - `tbd`: `未定` badge;
  - `elective`: `選択科目 X`.
- **Colors:** use `AppColors` tokens only (no hex literals), and `AppColors.onPrimary` on green.

- [ ] **Step 1: Write the failing widget tests:**
  - `cancelled slot shows strike-through and 休講`;
  - `elective slot shows 選択科目 X`;
  - `shows period times from SchoolPeriod`.
  - `week grid places school slot in its period row`: pump `SchoolWeekGrid` at 1024×800 with overridden providers, and find the subject text in the 2nd row, 3rd column.
  - `changes list shows 変更はありません when empty`.
- [ ] **Step 2:** Run `flutter test test/features/timetable/school_slot_card_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the card and the timeline merge.
- [ ] **Step 4:** Run `flutter analyze && flutter test`. Expected: 0 issues, PASS.

---

### Task 9: Reminders for school lessons

**Files:**
- Modify: `lib/core/services/notification_service.dart`
- Modify: `lib/features/school/school_providers.dart`: listen for week data and schedule reminders.
- Test: `test/core/notification_text_test.dart`, extend it.

**Interfaces:**
- Consumes: `SchoolDay`, `SchoolSlot`, `SchoolPeriod` (Task 6), and the existing `notif_class_rem_soon` / `notif_class_rem_title` keys.
- Produces:
  - `static Future<void> scheduleSchoolReminders(Map<String, SchoolDay> week, List<SchoolPeriod> periods)`.
    - For each day and each slot with status `normal` or `elective`, schedule a **one-shot** reminder (no `matchDateTimeComponents`) at start − 30 minutes, if that time is in the future.
    - Id = `'school_${date}_${period}'.hashCode`.
    - Before scheduling, cancel the ids for all periods of each of the 5 days, so removed or cancelled lessons lose their reminder.
  - `@visibleForTesting static String schoolReminderText(SchoolSlot slot, SchoolPeriod period)`. Uses `notif_class_rem_soon` with `n` = period label without `限` (e.g. `1・2`), `subject`, `room`, and `time` = `formatHm(period.start)`. It reuses the empty-room stripping of `classReminderText`.
- Wiring: in `school_providers.dart`, a `Provider` that `ref.listen`s `schoolWeekProvider(<this week's Monday>)` and calls `scheduleSchoolReminders` when the data changes. Watch it once from `AppShell` (or the same place that already triggers `syncAllReminders`). Skip when notifications are disabled; use the same flag the existing `syncAllReminders` path reads.

- [ ] **Step 1: Write the failing tests:**
  - `schoolReminderText uses school period start` (`13:10` for `5-6`);
  - `schoolReminderText strips empty room`.
- [ ] **Step 2:** Run `flutter test test/core/notification_text_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement as above.
- [ ] **Step 4:** Run `flutter analyze && flutter test`. Expected: 0 issues, PASS.

---

### Task 10: End-to-end check on emulators

**Files:** none new. Use a seed script at `functions/test/seed_emulator.mjs`, which writes the Task 1 fixture through the parse and diff code into the Firestore emulator.

- [ ] **Step 1:** Start the auth and firestore emulators. Run `node functions/test/seed_emulator.mjs school.test`. It writes:
  - `schools/school.test` with periods and courses;
  - `school_days` docs for the fixture weeks, using the real `parseTimetableRows` output.
- [ ] **Step 2:** Create the emulator user `a@school.test` with `emailVerified: true` through the Auth emulator REST API (`accounts:update` with `emailVerified`). Build the Android debug APK with `--dart-define=USE_EMULATOR=true` and install it on the `Pixel_9_Pro` emulator, the same way as in the 2026-10-20 notification test. Sign in.
- [ ] **Step 3:** Verify:
  - **Profile:** shows 農業 and 観光 chips.
  - **Timetable (week of the fixture's October dates):**
    - shows the 1年 農業 lessons with 4 periods, and 13:10 for 5・6限;
    - the cancelled slot is struck through;
    - personal classes still show with `自分`.
  - **Reminders:** `adb shell dumpsys alarm | grep eduplanner` shows school reminder alarms at start − 30 minutes.
- [ ] **Step 4:** Change one fixture cell (room) and re-run the seed with `--notify`. That script path calls `syncSchool` with fake Google deps and the real FCM disabled; assert the change count printed is 1. Take screenshots for the report.
- [ ] **Step 5 (web):**
  - Run `flutter build web --release --dart-define=USE_EMULATOR=true`. Clear IndexedDB first (CLAUDE.md lesson).
  - Sign in as the same emulator user through Playwright at widths 390, 768 and 1440.
  - Expected: 390 shows the day tabs + changes button; 768 shows the week grid; 1440 shows the grid + changes column. Take a screenshot of each.
- [ ] **Step 6:**
  - Append a dated entry to the `CLAUDE.md` Work Log, in Uzbek like the existing entries.
  - Tell the user which console steps from Task 5 remain, and that the deploy command is `firebase deploy --only functions,firestore:rules,hosting`.
