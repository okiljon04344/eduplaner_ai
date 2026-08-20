# Implementation Plan — Server Sync & Platform Bug Fixes

Fixing critical data exchange bugs between the mobile/desktop clients and the Firebase backend, focusing on timeouts, memory management, and platform-specific service initialisation.

## User Review Required

> [!IMPORTANT]
> **Cloud Functions Region Check**
> The current code uses the default Firebase region (`us-central1`). If you have deployed your functions to a different region (e.g., `asia-northeast1` for Japan), please let me know. I will add a central configuration to handle this.

> [!WARNING]
> **Desktop FCM Support**
> Firebase Messaging (FCM) has limited support on Windows and Linux. I will modify the `NotificationService` to skip remote token registration on these platforms to prevent startup hangs/crashes, while keeping local reminders active.

## Proposed Changes

### Core Infrastructure

#### [NEW] [functions_service.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/core/services/functions_service.dart)
A new centralized service to wrap all `httpsCallable` calls.
- **Unified Timeout:** Set to 120 seconds to match the longest server-side processes.
- **Error Mapping:** Converts technical Firebase errors into user-friendly localized strings.
- **Connectivity Check:** Verifies network availability before attempting heavy AI calls.

#### [MODIFY] [notification_service.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/core/services/notification_service.dart)
- Add platform checks (`defaultTargetPlatform`) to skip `getToken()` and permission requests on unsupported desktop OSs (Windows/Linux).
- Ensure `initialize()` never blocks the main app boot process even if a service is slow.

### Features & Logic

#### [MODIFY] [chat_repository.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/ai_chat/repositories/chat_repository.dart)
#### [MODIFY] [assignments_repository.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/assignments/repositories/assignments_repository.dart)
#### [MODIFY] [quiz_repository.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/quiz/repositories/quiz_repository.dart)
- Refactor to use the new `FunctionsService` instead of calling `FirebaseFunctions` directly.
- Remove redundant timeout configurations.

#### [MODIFY] [chat_provider.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/ai_chat/providers/chat_provider.dart)
- Improve context gathering: ensure `timetable` and `assignments` data is actually present before sending to AI, avoiding "empty context" bugs.

#### [MODIFY] [settings_screen.dart](file:///home/yashiloyceo/Desktop/eduplanner_ai/lib/features/settings/screens/settings_screen.dart)
- Apply the unified `FunctionsService` to the `deleteAccount` call, preventing client-side timeouts during full account wipe.

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no regression in types or service calls.
- Run `flutter test` to verify that existing data models and local logic still pass.

### Manual Verification
- **Desktop Simulation:** Run on a desktop target to verify the app boots instantly without hanging on notification init.
- **Timeout Test:** Trigger a heavy AI task (e.g., assignment check with a large file) and verify it completes without a "Deadline Exceeded" error on the client.
- **Offline Mode:** Turn off internet and verify that AI buttons show a clear "No Internet" toast instead of a generic exception.
