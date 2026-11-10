# Handoff: EduPlanner AI, school pilot prep (Claude Code → Gemini / agy)

Read this whole file first. Reply to the user **in Uzbek, Latin script only**. Never use Cyrillic.

## Goal and deadline
The school pilot with teachers is in December. The app must be finished, easy for first-time users and responsive on phone, tablet and PC by **2026-12-01**.

## State (2026-10-28 evening)
- Branch `feature/school-timetable-sync`. **Nothing is committed**, by design: the user commits only when asked.
- **Deployed by the user on 2026-10-28:** functions, firestore rules and hosting. The user is now testing on a phone as teacher and as student.
- **Design style: Green Neon stays.** The 「連絡帳」 paper/stamp redesign was shown on the Claude Design canvas (https://claude.ai/artifact/KxHL6quoXeJwEiBiCpQed9) and the user said no. Do not change `AppColors`, fonts or the theme.
- School timetable sync, Phase 1: done (spec `docs/design/school_timetable_sync_design_ja.md`, plan `docs/superpowers/plans/2026-10-27-school-timetable-sync-phase1.md`).
- Teacher input, Phase 2 part 1: done.
  - Server: `functions/school/overrides.js` and the callables `publishSchoolOverride`, `setSchoolTeacher` and `setSchoolStudentEdit` in `functions/index.js`.
  - Rules: `school_overrides` allows `get` by id only.
  - Client: `lib/features/school/` (`applyOverrides`, `schoolRoleProvider`, `schoolClassWeekProvider`) and the screen `screens/teacher_screen.dart` (route `/teacher`).
- Done on 2026-10-28:
  - **Desktop Home, 2 columns:** at ≥900px, lessons on the left and assignments plus AI on the right (`home_screen.dart`, `LayoutBuilder`).
  - **Notification permission:** no longer asked at launch. Home shows `NotificationPromptCard` once, on Android and iOS only (`NotificationService.needsPermissionPrompt`, `requestPermission`, `dismissPermissionPrompt`; the pref key is `notif_prompt_done`).
  - **Teacher screen:**
    - a 3-step first-run guide (`_TeacherGuide`, pref `teacher_guide_seen`);
    - a "生徒にはこう届きます" preview in the override sheet, which mirrors the server push text and is Japanese only;
    - a 「教員の登録」 app-bar button that scrolls to the registry.
  - **Teacher edit scope (§9.3):**
    - Data: `schools.teacherProfiles[email] = {name, homeroom: {grade, course} | null}`.
    - Who may edit: an admin; the homeroom teacher (担任) for every lesson of their class; or a teacher whose `name` appears in the lesson cell's `teacher` text. An empty slot (補講) is open to anyone who teaches that class on that day.
    - Server: `canEditSlot` in `overrides.js`, checked inside `publishOverride` through the `canEdit` dep. Client: `SchoolInfo.canEdit`.
    - **A teacher with no profile or no name can change nothing.** After deploy, the admin must enter each teacher's timetable name in 教員の登録.
  - **Student class lock:**
    - `schools.allowStudentEdit` is an admin switch (`setSchoolStudentEdit`).
    - When it is off, a linked student's saved 学年/コース cannot change. This is enforced in `firestore.rules` (`users` update, `classLocked()`) and in `profile_setup_screen.dart` (chips disabled, `school_edit_locked` message). The first save is always open.
- Also done on 2026-10-28:
  - The teacher registry moved to its own admin page, `/school-admin` (`SchoolAdminScreen`). It opens from a Settings row and from the 教員メニュー app bar.
  - **教員メニュー at ≥1100px:** the class list (担当クラス) on the left, with the homeroom class first; the week in the middle; and the edit panel on the right.
  - **「今日」 button:** shown in the week bar when another week is open.
- Checks: `flutter analyze` clean, `flutter test` 151 pass, `cd functions && npm test` 37 pass, `npm run lint` clean. Emulator checks also passed: rules 403/200, the callables, and Playwright at 390, 768 and 1440.

## Rules
- Do NOT commit, push or deploy. The user runs `firebase deploy` themselves.
- Keep `flutter analyze` at "No issues found!" and keep every test green. Add a test for each new rule or branch of logic.
- **UI strings:** UI text goes through `AppStrings.t()`. New keys go into all 21 files in `assets/l10n/*.json`, written with Python `json.dump(..., ensure_ascii=False, indent=2, sort_keys=True)` plus a trailing newline. `test/core/l10n_parity_test.dart` fails if any locale is missing a key.
- **Colors:** `AppColors` surface and text tokens are mutable, so derived styles must be getters, never `static const`. Use `AppColors.onPrimary` for text on green. Never hardcode hex values in new code.
- **Edit scope:** server and client must agree. If you change `canEditSlot` (JS), change `SchoolInfo.canEdit` (Dart) too, plus the tests on both sides.
- **Field paths:** emails contain dots. Never build a Firestore field path like `teacherProfiles.${email}`; use `FieldPath` or a nested map, as `setSchoolTeacher` does.
- **Secrets:** never put a secret, client secret or refresh token in a script, a file or a chat.
- **Privacy:** never copy real school file contents or teacher names into the repo. Use made-up names (田中, 鈴木, 佐藤) only.
- **Formatting:** do not run `dart format` on whole existing files. It rewrites unrelated lines.

## How to test UI (works, use it)
Scripts are in `tool/ui_check/`:
- `seed_users.py` creates the emulator test users:
  - `tanaka@school.test`: admin, name 田中, 担任 of 1年・農業;
  - `suzuki@school.test`: teacher, name 鈴木, no homeroom;
  - `yamada@school.test`: plain homeroom teacher of 2年・観光, not an admin;
  - `s1001@school.test`: student, 1年・農業.

  The password for all three is `test-pass-123`.
- `spa.py <build/web>` runs an SPA server on 8098.
- `pw/run.mjs <profile> <w> <h> '<json steps>'` runs Playwright. Screenshots go to `tool/ui_check/shots/`.

Example steps: `[["login","tanaka@school.test",[195,364,180,426,195,582,248,379,195,525]],["click",335,27],["nav","/teacher"],["wait",2500],["shot","teacher_390"],["resize",1440,900]]`.
- The login coordinates are for 390x844.
- `["click",335,27]` taps スキップ on the onboarding screen a fresh profile lands on.

1. Start the emulators:
   ```bash
   firebase emulators:start --only auth,firestore,functions --project eduplannerai-97365
   ```
2. Seed the timetable, then the users:
   ```bash
   cd functions && FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 GCLOUD_PROJECT=eduplannerai-97365 node test/seed_emulator.mjs school.test && python3 ../tool/ui_check/seed_users.py
   ```
3. Build the web app for the emulators:
   ```bash
   flutter build web --release --dart-define=USE_EMULATOR=true
   ```
   Serve it with `python3 tool/ui_check/spa.py build/web`.
4. Drive it with Playwright and headless Chrome (`/usr/bin/google-chrome`).
   - The URL strategy is **hash** (`#/home`).
   - An emulator session does not survive a reload. Sign in once, then move between screens with `location.hash` (the `nav` step).
5. **Never deploy an emulator build.** The release command is in "Deploy" below.

## Running Gemini headless (agy -p)
`agy -p` in headless mode auto-denies every tool that needs the "command" or "mcp" permission, so it stops without doing anything. `~/.gemini/antigravity-cli/settings.json` only allows `ls`, `grep` and `agy`. Do not widen that file unless the user agrees. Otherwise run interactively (`agy -i`) so the user can approve each step.

## Next tasks, in order
1. **Fix whatever the user finds in phone testing first.** Ask for screenshots.
3. **Phase 2, remaining features** (spec §9.2-3 to §9.2-6):
   - 課題配布 (`school_assignments` and `school_assignment_progress`);
   - お知らせボード with 既読 (`school_notices` and `school_notice_reads`). A 担任 may send to the whole class; scope it with the same profile data;
   - 選択科目グループ X/Y/Z;
   - archive overrides 24 hours after the lesson;
   - "ファイルに合わせる" for unresolved overrides.
4. **Native Android check** on the `Pixel_9_Pro` emulator: build with `--dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=10.0.2.2`. The AVD network was unreachable on 10-27; FlutterFire remaps localhost to 10.0.2.2.
5. **Dark-mode pass** at the three widths.
6. **Open questions:** whether school users should still see "クラス共有" (study groups); the login validator error that stays visible after the field is filled.

## Deploy (user runs it)
```bash
cd ~/Desktop/eduplanner_ai && flutter build web --release && firebase deploy --only functions,firestore:rules,hosting
```

The Android phone app needs its own rebuild and install to get new client code. A web deploy is not enough.
