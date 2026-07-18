#!/usr/bin/env bash
#
# Build, sign, notarize, and package withoutBG for release.
#
# Prerequisites:
#   - Xcode 16+ with command-line tools
#   - Apple Developer Program membership
#   - DEVELOPMENT_TEAM set in project.yml (or export DEVELOPMENT_TEAM=...)
#   - Developer ID Application certificate in Keychain
#   - Notarization credentials (one of):
#       NOTARY_PROFILE=keychain profile from `xcrun notarytool store-credentials`
#       APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password)
#       ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH (App Store Connect API key)
#
# Usage:
#   ./scripts/release.sh                  # DMG for direct download
#   ./scripts/release.sh --app-store      # upload to App Store Connect
#   ./scripts/release.sh --skip-notarize  # build + DMG only (local testing)
#
set -euo pipefail

# Use full Xcode when xcode-select points at Command Line Tools only.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="WithoutBG"
APP_NAME="withoutBG"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/${SCHEME}.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$ROOT/dist"
EXPORT_OPTIONS_TEMPLATE="$ROOT/scripts/ExportOptions-direct.plist"

SKIP_XCODEGEN=0
SKIP_ARCHIVE=0
SKIP_NOTARIZE=0
SKIP_DMG=0
APP_STORE=0
BUILD_SERVER=0

usage() {
  cat <<'EOF'
Build, sign, notarize, and package withoutBG for release.

Prerequisites:
  - Xcode 16+ with command-line tools
  - Apple Developer Program membership
  - DEVELOPMENT_TEAM set in project.yml (or export DEVELOPMENT_TEAM=...)
  - Developer ID Application certificate in Keychain
  - Notarization credentials (one of):
      NOTARY_PROFILE=keychain profile from `xcrun notarytool store-credentials`
      APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (app-specific password)
      ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH (App Store Connect API key)

Usage:
  ./scripts/release.sh                  # withoutBG DMG (primary)
  ./scripts/release.sh --server           # WithoutBG Server headless DMG
  ./scripts/release.sh --app-store      # upload to App Store Connect
  ./scripts/release.sh --skip-notarize  # build + DMG only (local testing)

EOF
  echo "Options:"
  echo "  --server          Build WithoutBG Server (headless) instead of desktop"
  echo "  --skip-notarize   Skip notarization and stapling"
  echo "  --skip-dmg        Skip DMG creation (direct download path only)"
  echo "  --skip-archive    Re-use existing $ARCHIVE_PATH"
  echo "  --no-xcodegen     Do not run xcodegen before building"
  echo "  -h, --help        Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) BUILD_SERVER=1; SCHEME="WithoutBGServer"; APP_NAME="WithoutBG Server" ;;
    --app-store) APP_STORE=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --skip-dmg) SKIP_DMG=1 ;;
    --skip-archive) SKIP_ARCHIVE=1 ;;
    --no-xcodegen) SKIP_XCODEGEN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ "$APP_STORE" -eq 1 ]]; then
  SKIP_NOTARIZE=1
  SKIP_DMG=1
  EXPORT_OPTIONS_TEMPLATE="$ROOT/scripts/ExportOptions-appstore.plist"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

read_project_yaml() {
  local key="$1"
  grep "${key}:" "$ROOT/project.yml" | head -1 | sed -E 's/.*: *"?([^"]*)"?.*/\1/'
}

TEAM_ID="${DEVELOPMENT_TEAM:-$(read_project_yaml DEVELOPMENT_TEAM)}"
MARKETING_VERSION="$(read_project_yaml MARKETING_VERSION)"
CURRENT_PROJECT_VERSION="$(read_project_yaml CURRENT_PROJECT_VERSION)"

require_cmd xcodebuild

if [[ -z "$TEAM_ID" ]]; then
  echo "error: DEVELOPMENT_TEAM is empty." >&2
  echo "Set it in project.yml or export DEVELOPMENT_TEAM before running." >&2
  exit 1
fi

if [[ "$SKIP_XCODEGEN" -eq 0 ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Generating Xcode project"
    xcodegen generate
  elif [[ ! -d "$ROOT/WithoutBG.xcodeproj" ]]; then
    echo "error: WithoutBG.xcodeproj missing and xcodegen not installed." >&2
    echo "Install with: brew install xcodegen" >&2
    exit 1
  fi
fi

if [[ ! -d "$ROOT/WithoutBG.xcodeproj" ]]; then
  echo "error: WithoutBG.xcodeproj not found." >&2
  exit 1
fi

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME-notarize.zip"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
DMG_NAME="withoutBG-${MARKETING_VERSION}.dmg"
if [[ "$BUILD_SERVER" -eq 1 ]]; then
  DMG_NAME="WithoutBG-Server-${MARKETING_VERSION}.dmg"
fi
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Release withoutBG ${MARKETING_VERSION} (${CURRENT_PROJECT_VERSION})"
echo "    Team: $TEAM_ID"

if [[ "$SKIP_ARCHIVE" -eq 0 ]]; then
  echo "==> Archiving ($SCHEME, Release)"
  xcodebuild \
    -project "$ROOT/WithoutBG.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'platform=macOS,arch=arm64' \
    EXCLUDED_ARCHS=x86_64 \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive
else
  if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "error: --skip-archive set but archive not found at $ARCHIVE_PATH" >&2
    exit 1
  fi
  echo "==> Using existing archive: $ARCHIVE_PATH"
fi

echo "==> Exporting signed app"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$EXPORT_OPTIONS_TEMPLATE" > "$EXPORT_OPTIONS_PLIST"
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: exported app not found at $APP_PATH" >&2
  exit 1
fi

if [[ "$APP_STORE" -eq 1 ]]; then
  echo
  echo "Done. Build uploaded to App Store Connect (or ready in $EXPORT_DIR)."
  echo "Open https://appstoreconnect.apple.com to assign the build in TestFlight / submit for review."
  exit 0
fi

notary_submit() {
  local artifact="$1"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$artifact" \
      --key "$ASC_KEY_PATH" \
      --key-id "$ASC_KEY_ID" \
      --issuer "$ASC_ISSUER_ID" \
      --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$artifact" \
      --apple-id "$APPLE_ID" \
      --team-id "${APPLE_TEAM_ID:-$TEAM_ID}" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
  else
    echo "error: notarization credentials not configured." >&2
    echo "Set one of:" >&2
    echo "  NOTARY_PROFILE          (recommended — run: xcrun notarytool store-credentials withoutBG-notary)" >&2
    echo "  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH" >&2
    echo "  APPLE_ID, APPLE_APP_PASSWORD [, APPLE_TEAM_ID]" >&2
    echo "Or pass --skip-notarize for a local unsigned-for-Gatekeeper build." >&2
    exit 1
  fi
}

notarize_app() {
  echo "==> Submitting app for notarization"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  notary_submit "$ZIP_PATH"
  rm -f "$ZIP_PATH"

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
}

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  notarize_app
else
  echo "==> Skipping notarization"
fi

create_dmg() {
  local dmg_path="$1"
  echo "==> Creating DMG: $dmg_path"

  if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
      --volname "withoutBG" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --app-drop-link 450 185 \
      "$dmg_path" \
      "$APP_PATH"
    return
  fi

  echo "    create-dmg not found; using hdiutil (install create-dmg for a nicer layout: brew install create-dmg)"
  local staging
  staging="$(mktemp -d)"
  trap 'rm -rf "$staging"' RETURN
  cp -R "$APP_PATH" "$staging/"
  ln -s /Applications "$staging/Applications"
  rm -f "$dmg_path"
  hdiutil create -volname "withoutBG" -srcfolder "$staging" -ov -format UDZO "$dmg_path" >/dev/null
}

if [[ "$SKIP_DMG" -eq 0 ]]; then
  rm -f "$DMG_PATH"
  create_dmg "$DMG_PATH"
fi

echo
echo "Release artifacts:"
echo "  App:  $APP_PATH"
if [[ "$SKIP_DMG" -eq 0 ]]; then
  echo "  DMG:  $DMG_PATH"
fi
echo
echo "Next: upload the DMG to GitHub Releases or your website."
