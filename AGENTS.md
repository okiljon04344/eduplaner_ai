# EduPlanner AI — Claude Code Agent Instructions

## Project Identity
Flutter mobile app. AI-powered student study management. Japanese vocational school graduation project.
Target: iOS + Android. Language: Dart (Flutter). Backend: Firebase. AI: Google Gemini 1.5 Flash.

## Non-negotiable rules
- Zero TODOs in any file you produce. Every method must be fully implemented.
- Zero `throw UnimplementedError()` except inside abstract class definitions.
- Every `AsyncValue` must handle `.when(data:, loading:, error:)` or use `.valueOrNull ?? fallback`.
- Never force-unwrap with `!` without a prior null check.
- All user-visible strings and error messages in Japanese.
- Never hardcode API keys. Always read from `flutter_secure_storage`.
- `const` constructors wherever possible.
- Always `dispose()` TextEditingController, AnimationController, ScrollController, StreamSubscription.
- All Firestore writes use `Timestamp.fromDate()` or `FieldValue.serverTimestamp()`.
- Navigation: `context.go()` to replace, `context.push()` to layer. Never `Navigator.push` directly.

## Tech stack (exact versions — required for AGP 9.0 compatibility)
```
flutter_riverpod: ^2.5.1
riverpod_annotation: ^2.3.5
go_router: ^14.2.0
firebase_core: ^4.13.0
firebase_auth: ^6.5.7
cloud_firestore: ^6.8.0
firebase_messaging: ^16.5.0
firebase_analytics: ^12.4.6
cloud_functions: ^6.3.6
google_generative_ai: ^0.4.6
google_sign_in: ^7.2.0
fl_chart: ^0.69.0
flutter_animate: ^4.5.0
table_calendar: ^3.1.2
intl: ^0.20.2
flutter_local_notifications: ^17.2.3
timezone: ^0.9.4
shared_preferences: ^2.3.2
flutter_secure_storage: ^9.2.2
toastification: ^2.1.0
uuid: ^4.4.2
dio: ^5.7.0
freezed: ^2.5.7
json_serializable: ^6.8.0
file_picker: ^12.0.0
```

## Design tokens — Green Neon (2026-08-19 redesign)

**`lib/core/theme/app_colors.dart` is the single source of truth. Do NOT hardcode
color hex values from this section into new code, and do NOT regenerate
`app_colors.dart`/`app_theme.dart` from this doc — read the actual file.** This
section is a human-readable summary only, kept in sync by hand; if it and the
Dart file ever disagree, the Dart file wins. (A prior session had this
backwards — some tooling regenerated `app_colors.dart` from an older,
now-wrong version of this section and reverted the entire app to a stale
indigo/purple palette, breaking ~26 call sites. Don't repeat that.)

```dart
// Brand accent (same literal value in both themes)
primary      = Color(0xFF06D6A0)  // green
primaryMid   = Color(0xFF34D399)  // green mid
primaryLight = Color(0xFF5EEAD4)  // green light
primaryDark  = Color(0xFF059669)  // green deep (== primaryIndigo)
danger       = Color(0xFFF87171)
success      = Color(0xFF34D399)

// Surface/text — mutable statics on AppColors, reassigned by
// AppColors.applyBrightness(Brightness). Read the current value from
// AppColors.xxx at call time; never cache/const it.
                  dark        light
background        0xFF100C08  0xFFFFFFFF
surface            0xFF17120A  0xFFFFFFFF
bgLayer            0xFF241C10  0xFFF0FDF9   (dialogs/sheets/chat bubble bg)
bgInput            0xFF221A0E  0xFFFFFFFF
textPrimary        0xFFFFF3E8  0xFF1C1917
textSecondary      80%D1FAE5   0xFF9CA3AF
textOnHero (theme-aware — dark:white / light:textPrimary; NEVER hardcode
  Colors.white on a hero/gradient panel, light-mode hero backgrounds are pale)

// Subject colors — UNCHANGED from the original design, kept deliberately
// (per-subject color-coding is real, useful functionality; the new design
// mockup's "green family only" suggestion was not applied to these).
数学:          fill(0x1FFBBF24) text(dark 0xFFFBBF24 / light 0xFFB45309) dot(0xFFFBBF24/0xFFF59E0B)
英語:          fill(0x1FF472B6) text(dark 0xFFF472B6 / light 0xFF9D174D) dot(0xFFF472B6/0xFFEF4444)
プログラミング:  fill(0x26A855F7) text(dark 0xFFC084FC / light 0xFF6D28D9) dot(0xFFA855F7/0xFF6C5CE7)
物理:          fill(0x1F60A5FA) text(dark 0xFF60A5FA / light 0xFF1D4ED8) dot(0xFF60A5FA/0xFF74B9FF)
化学:          fill(0x1F34D399) text(dark 0xFF34D399 / light 0xFF065F46) dot(0xFF34D399/0xFF10B981)
歴史:          fill(0x1FF87171) text(dark 0xFFF87171 / light 0xFF991B1B) dot(0xFFF87171/0xFFEF4444)

// Border radius
cards: 20-22px | buttons: 14-16px | chips/pills: 20px | inputs: 16px
bottom-sheet top corners: 24px

// Elevation — dark mode: no box shadows, border only. Light mode: soft
// shadows OK (see AppColors.cardShadow). Glow/pulse shadows use
// primaryMid at low alpha, e.g. BoxShadow(color: primaryMid.withValues(alpha: 0.5), blurRadius: 20).
```

Fonts: Plus Jakarta Sans (400/600/700/800) body/UI, Space Grotesk (700) for
stat numbers only, both via `google_fonts`, `NotoSansJP` fallback for CJK
glyphs (Plus Jakarta Sans/Space Grotesk have no Japanese coverage).

## File structure
```
lib/
├── main.dart
├── app.dart
├── firebase_options.dart          ← placeholder, user runs flutterfire configure
├── core/
│   ├── theme/
│   │   ├── app_colors.dart
│   │   ├── app_text_styles.dart
│   │   └── app_theme.dart
│   ├── router/app_router.dart
│   ├── constants/
│   │   ├── subject_colors.dart
│   │   └── api_constants.dart
│   ├── providers/
│   │   ├── app_providers.dart     ← all repository providers
│   │   └── theme_provider.dart
│   ├── services/notification_service.dart
│   └── utils/
│       ├── date_helper.dart
│       └── validators.dart
├── features/
│   ├── auth/
│   │   ├── models/user_model.dart
│   │   ├── repositories/auth_repository.dart
│   │   ├── providers/auth_provider.dart
│   │   └── screens/login_screen.dart
│   ├── home/
│   │   ├── providers/home_provider.dart
│   │   ├── screens/home_screen.dart
│   │   └── widgets/
│   │       ├── greeting_header.dart
│   │       ├── weekly_progress_card.dart
│   │       ├── today_classes_row.dart
│   │       ├── class_mini_card.dart
│   │       ├── upcoming_assignments_list.dart
│   │       ├── assignment_row_item.dart
│   │       └── ai_study_tip_card.dart
│   ├── timetable/
│   │   ├── models/class_model.dart
│   │   ├── repositories/timetable_repository.dart
│   │   ├── providers/timetable_provider.dart
│   │   ├── screens/timetable_screen.dart
│   │   └── widgets/
│   │       ├── timetable_grid.dart
│   │       ├── day_header_row.dart
│   │       ├── period_column.dart
│   │       ├── class_cell.dart
│   │       ├── empty_cell.dart
│   │       ├── subject_legend.dart
│   │       ├── add_edit_class_sheet.dart
│   │       └── class_detail_sheet.dart
│   ├── assignments/
│   │   ├── models/assignment_model.dart
│   │   ├── repositories/assignments_repository.dart
│   │   ├── providers/assignments_provider.dart
│   │   ├── screens/assignments_screen.dart
│   │   └── widgets/
│   │       ├── assignment_card.dart
│   │       ├── filter_chips_row.dart
│   │       ├── weekly_progress_ring.dart
│   │       ├── progress_bar_row.dart
│   │       ├── add_edit_assignment_sheet.dart
│   │       └── assignment_detail_sheet.dart
│   ├── ai_chat/
│   │   ├── models/message_model.dart
│   │   ├── repositories/chat_repository.dart
│   │   ├── providers/chat_provider.dart
│   │   ├── screens/ai_chat_screen.dart
│   │   └── widgets/
│   │       ├── chat_bubble.dart
│   │       ├── typing_indicator.dart
│   │       ├── quick_reply_chips.dart
│   │       └── chat_input_bar.dart
│   └── settings/screens/settings_screen.dart
└── shared/
    ├── widgets/
    │   ├── app_shell.dart
    │   ├── app_bottom_nav.dart
    │   ├── donut_chart.dart
    │   ├── subject_pill.dart
    │   ├── status_badge.dart
    │   ├── star_rating.dart
    │   ├── app_input_field.dart
    │   ├── section_header.dart
    │   └── confirm_dialog.dart
    └── models/subject_model.dart
```

## After generating all files, always run
```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```
Fix every error before finishing.
