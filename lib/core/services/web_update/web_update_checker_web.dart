import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'update_decision.dart';

const _kBuildFile = 'app_build.json';
const _kAttemptKey = 'eduplanner.updateAttempt';
const _kPollInterval = Duration(minutes: 10);

bool _started = false;
bool _checking = false;
String? _pendingBuildId;

/// Starts the update check. Safe to call more than once.
///
/// - On start: if the server already has a newer build, reload right away
///   (the app has only just opened, so no user input is lost).
/// - Every 10 minutes while open: only *remember* a newer build — never
///   reload under the user's fingers mid-form.
/// - When the tab/PWA comes back to the foreground: reload onto the newer
///   build if one is known (or found now).
void startWebUpdateChecker() {
  if (_started || kAppBuildId.isEmpty) return;
  _started = true;

  unawaited(_check(reloadIfNew: true));

  Timer.periodic(_kPollInterval, (_) {
    if (web.document.visibilityState == 'visible') {
      unawaited(_check(reloadIfNew: false));
    }
  });

  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'visible') {
        unawaited(_check(reloadIfNew: true));
      }
    }).toJS,
  );
}

Future<void> _check({required bool reloadIfNew}) async {
  if (_checking) return;
  _checking = true;
  try {
    final remote = await _fetchRemoteBuildId() ?? _pendingBuildId;
    if (!UpdateDecision.hasNewBuild(currentBuildId: kAppBuildId, remoteBuildId: remote)) {
      _pendingBuildId = null;
      return;
    }
    _pendingBuildId = remote;
    if (!reloadIfNew) return;

    final storage = web.window.sessionStorage;
    final shouldReload = UpdateDecision.shouldReload(
      currentBuildId: kAppBuildId,
      remoteBuildId: remote,
      lastAttemptedBuildId: storage.getItem(_kAttemptKey),
    );
    if (!shouldReload) return;

    storage.setItem(_kAttemptKey, remote!);
    debugPrint('Web update: $kAppBuildId -> $remote, reloading');
    web.window.location.reload();
  } catch (e) {
    // Offline or blocked: keep running the current build, try again later.
    debugPrint('Web update check failed: $e');
  } finally {
    _checking = false;
  }
}

/// Fetches `app_build.json` bypassing every cache layer (browser HTTP cache
/// via `no-store`, intermediaries via the unique query string).
Future<String?> _fetchRemoteBuildId() async {
  final url = '$_kBuildFile?t=${DateTime.now().millisecondsSinceEpoch}';
  final response = await web.window
      .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
      .toDart;
  if (!response.ok) return null;
  final body = (await response.text().toDart).toDart;
  return UpdateDecision.parseBuildId(jsonDecode(body));
}
