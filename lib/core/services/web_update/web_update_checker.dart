/// Keeps the web build fresh: after a new deploy, open tabs and home-screen
/// PWAs reload onto the new code instead of running the old bundle forever.
///
/// No-op on Android/iOS/desktop (store/APK updates handle those).
library;

export 'web_update_checker_stub.dart'
    if (dart.library.js_interop) 'web_update_checker_web.dart';
