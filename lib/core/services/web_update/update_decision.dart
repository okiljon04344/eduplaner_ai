/// Build id baked into this bundle by `tool/deploy_web.sh`
/// (`--dart-define=APP_BUILD_ID=...`). Empty in `flutter run` / dev builds,
/// which disables the web update check entirely.
const kAppBuildId = String.fromEnvironment('APP_BUILD_ID');

/// Pure decision logic for the web update check, kept free of browser APIs
/// so it can be unit-tested on the VM.
abstract final class UpdateDecision {
  /// Whether the server has a different build than the one running.
  ///
  /// A missing/blank [remoteBuildId] (network error, file not deployed yet)
  /// never counts as an update, so a flaky fetch cannot cause a reload.
  static bool hasNewBuild({
    required String currentBuildId,
    required String? remoteBuildId,
  }) {
    if (currentBuildId.isEmpty) return false;
    final remote = remoteBuildId?.trim() ?? '';
    return remote.isNotEmpty && remote != currentBuildId;
  }

  /// Whether to reload now for [remoteBuildId].
  ///
  /// [lastAttemptedBuildId] is the build we already reloaded for in this
  /// browser session. If we reloaded for it and still run an older bundle
  /// (CDN propagation lag, a proxy ignoring headers), reloading again would
  /// loop forever — so each remote build gets exactly one reload per session.
  static bool shouldReload({
    required String currentBuildId,
    required String? remoteBuildId,
    required String? lastAttemptedBuildId,
  }) {
    if (!hasNewBuild(currentBuildId: currentBuildId, remoteBuildId: remoteBuildId)) {
      return false;
    }
    return lastAttemptedBuildId != remoteBuildId!.trim();
  }

  /// Extracts `buildId` from the `app_build.json` body; null when malformed.
  static String? parseBuildId(Object? json) {
    if (json is! Map) return null;
    final id = json['buildId'];
    return id is String && id.trim().isNotEmpty ? id.trim() : null;
  }
}
