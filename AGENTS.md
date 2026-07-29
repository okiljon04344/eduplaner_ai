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

## Tech stack (exact versions — do not change)
```
flutter_riverpod: ^2.5.1
riverpod_annotation: ^2.3.5
go_router: ^14.2.0
firebase_core: ^3.4.0
firebase_auth: ^5.2.0
cloud_firestore: ^5.3.0
firebase_messaging: ^15.1.0
google_generative_ai: ^0.4.6
google_sign_in: ^6.2.1
fl_chart: ^0.69.0
flutter_animate: ^4.5.0
table_calendar: ^3.1.2
intl: ^0.19.0
flutter_local_notifications: ^17.2.3
timezone: ^0.9.4
shared_preferences: ^2.3.2
flutter_secure_storage: ^9.2.2
toastification: ^2.1.0
uuid: ^4.4.2
dio: ^5.7.0
freezed: ^2.5.7
json_serializable: ^6.8.0
```

## Design tokens (use these exact values everywhere)
```dart
// Colors
primary       = Color(0xFF4F46E5)
primaryLight  = Color(0xFFEEF2FF)
success       = Color(0xFF10B981)
successLight  = Color(0xFFD1FAE5)
warning       = Color(0xFFF97316)
warningLight  = Color(0xFFFFF7ED)
danger        = Color(0xFFDC2626)
dangerLight   = Color(0xFFFEF2F2)
textPrimary   = Color(0xFF111827)
textSecondary = Color(0xFF6B7280)
textMuted     = Color(0xFF9CA3AF)
border        = Color(0xFFE5E7EB)
borderLight   = Color(0xFFF3F4F6)
surface       = Color(0xFFFFFFFF)
background    = Color(0xFFF9FAFB)

// Subject colors
数学:          fill(0xFFDBEAFE) text(0xFF1D4ED8) dot(0xFF3B82F6)
英語:          fill(0xFFFEF3C7) text(0xFFB45309) dot(0xFFF59E0B)
プログラミング:  fill(0xFFEDE9FE) text(0xFF6D28D9) dot(0xFF8B5CF6)
物理:          fill(0xFFD1FAE5) text(0xFF065F46) dot(0xFF10B981)
化学:          fill(0xFFFCE7F3) text(0xFF9D174D) dot(0xFFEC4899)
歴史:          fill(0xFFFEE2E2) text(0xFF991B1B) dot(0xFFEF4444)

// Border radius
cards: 16px | buttons: 14px | chips: 20px | inputs: 12px
bottom-sheet top corners: 24px | timetable cells: 10px

// Elevation — NO box shadows on cards. Border only.
cards: Border.all(color: border, width: 1)
FAB:   BoxShadow(color: Color(0x604F46E5), blurRadius: 16, offset: Offset(0, 6))
```

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
