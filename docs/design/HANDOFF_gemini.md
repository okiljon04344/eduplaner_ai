# Handoff: 学校時間割連携 設計書 (Claude Code → Gemini CLI)

Read this whole file before doing anything. Also read `CLAUDE.md`, `AGENTS.md`, and `GEMINI_CONTEXT.md` in the repository root.

## Task
Continue the design document `docs/design/school_timetable_sync_design_ja.md`. It is a draft from 2026-10-27 that the user is reviewing. **This is design work only. Do not write product code** (Dart, functions, or rules) until the user explicitly approves the design.

## How to work with the user
- Reply to the user **in Uzbek, Latin script only**. Never use Cyrillic.
- Write the design document itself **in Japanese**, because it is meant for school staff and teachers. Keep the existing structure (§1–§14) and style.
- Ask one question at a time. Where a decision has an obvious default, propose a recommendation.
- Do not commit, push, or deploy. The user runs deploys and privileged commands themselves.

## Decisions already made by the user (do not re-open)
1. **Phase 1** uses the school's existing timetable file as-is. It is `2026年度 後期時間割.xlsx` on Google Drive, owned by a teacher and shared inside the `ihit.ac.jp` domain. Students enter nothing.
2. **Sync** runs every day at **08:00 and 17:00 JST**. It sends a push only to the classes that changed.
3. **Manual entry stays.** Students can still add their own classes.
4. **Later phases:** the school also makes other files, such as the yearly 年間予定表, and these will be imported too (Phase 3). There must also be a **teacher input place** for updates: 休講, 教室変更, 補講, 課題, お知らせ (Phase 2).
5. **Schools are identified by email domain.** The domain comes from the verified Google account email.
6. **Access method B:** one domain member links the file once with the `drive.file` scope and the Google Picker, and the server reads it. Do not use `drive.readonly` (a restricted scope that triggers a paid security assessment). Method C (Apps Script) is the fallback only if the school admin blocks third-party apps.

## Facts about the real file (structure only)
- One block per week, with dates (late September to December). In each block the left half is 1年生 and the right half is 2年生, with columns 月–金.
- Each block has four 90-minute slots (コマ), with a 休憩 break between the second and third:

  | Slot | Time |
  |---|---|
  | 1・2限目 | 09:00–10:30 |
  | 3・4限目 | 10:40–12:10 |
  | 5・6限目 | 13:10–14:40 |
  | 7・8限目 | 14:50–16:20 |

- Each slot has two courses, 農業 and 観光, with two rows each: the subject row, then a `担当【教室】` row.
- Changes are written into the cells as text, for example `英語休講`, `休み`, `学園祭準備`, `宿泊研修`, `企業説明会`, `時間は追って連絡`. `X`/`Y`/`Z` appear too and are not yet understood.
- **Privacy:** the file contains real teacher names. Never copy real names or cell contents into the repository or the design document. Use made-up names (田中, 鈴木) in examples.

## Remaining work on the design document
1. Walk the user through §13 (未決事項) one item at a time and record each answer in the document.
2. Deepen §9 (教員入力): screen list, the flow for each action, and how teacher overrides resolve against the next sheet sync. The canvas design "時間割の編集（PC）" and the `Renraku*` boards are visual references.
3. Add a Phase 3 section for the 年間予定表 adapter once the user says where that file lives. Read it **structure only**, the same way as the timetable file.
4. Check that §10 (data model) and §12 (security) still match after the edits.
5. When the user approves the document, hand the work back to Claude Code to write the implementation plan. Do not start implementing yourself.

## Existing code to be aware of (read, don't change)
- `lib/core/constants/periods.dart` hard-codes six 90-minute periods, with 3限 at 13:00. This school's periods differ, so the design moves period times into `schools/{domain}.periods`.
- `lib/features/auth/models/user_model.dart` already has `grade` and `course`, which are reused for 学年 and コース.
- `study_groups` and `joinGroupByCode` are the current class-sharing mechanism by code. The design adds domain-based classes and keeps the code-based groups.
- `functions/index.js` has the `onClassStatusChanged` push pattern and `enforceAiQuota`, which are examples of server-side patterns.
