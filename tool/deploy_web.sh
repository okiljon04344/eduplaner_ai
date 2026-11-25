#!/usr/bin/env bash
# Builds the Flutter web app with a unique build id and deploys it to
# Firebase Hosting. Open tabs / home-screen PWAs compare their baked-in id
# with build/web/app_build.json and reload onto the new code
# (lib/core/services/web_update/).
#
# Usage:
#   ./tool/deploy_web.sh                       # build + deploy hosting
#   ./tool/deploy_web.sh --no-deploy           # build only (check locally)
#   RECAPTCHA_SITE_KEY=xxx ./tool/deploy_web.sh  # with App Check on web
set -euo pipefail

cd "$(dirname "$0")/.."

DEPLOY=1
[[ "${1:-}" == "--no-deploy" ]] && DEPLOY=0

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Commit qilinmagan o'zgarishlar bor — build id'da '-dirty' bo'ladi."
fi

DIRTY=""
git diff --quiet && git diff --cached --quiet || DIRTY="-dirty"
BUILD_ID="$(git rev-parse --short HEAD)${DIRTY}-$(date -u +%Y%m%d%H%M%S)"
echo "▶ Build id: ${BUILD_ID}"

ARGS=(--release "--dart-define=APP_BUILD_ID=${BUILD_ID}")
if [[ -n "${RECAPTCHA_SITE_KEY:-}" ]]; then
  ARGS+=("--dart-define=RECAPTCHA_SITE_KEY=${RECAPTCHA_SITE_KEY}")
else
  echo "ℹ️  RECAPTCHA_SITE_KEY yo'q — vebda App Check o'chiq bo'ladi."
fi

# A stale web plugin registrant once dropped plugins from the build
# (see CLAUDE.md work log, 2026-11-10).
rm -rf .dart_tool/flutter_build

flutter pub get
flutter build web "${ARGS[@]}"

printf '{"buildId":"%s"}\n' "${BUILD_ID}" > build/web/app_build.json

if ! grep -q "${BUILD_ID}" build/web/main.dart.js; then
  echo "❌ Build id main.dart.js ichiga tushmadi — deploy to'xtatildi." >&2
  exit 1
fi
echo "✔ build/web tayyor (app_build.json + main.dart.js bir xil id)."

if [[ "${DEPLOY}" == "1" ]]; then
  firebase deploy --only hosting
  echo "✔ Deploy tugadi. Ochiq tablar keyingi safar ekranga qaytganda yangilanadi."
fi
