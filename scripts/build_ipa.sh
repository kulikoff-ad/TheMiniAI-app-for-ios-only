#!/usr/bin/env bash
#
# Build an IPA for AI Agent Hub.
#
#   Signed (for a device / TestFlight):
#       ./scripts/build_ipa.sh --team ABCDE12345
#
#   Unsigned (for simulators, sideloading tools such as AltStore/Sideloadly,
#   or re-signing later):
#       ./scripts/build_ipa.sh --unsigned
#
# Requires macOS with Xcode 16 or newer.

set -euo pipefail

SCHEME="AIAgentHub"
PROJECT="AIAgentHub.xcodeproj"
CONFIG="Release"
BUILD_DIR="build"
TEAM_ID=""
UNSIGNED=0
METHOD="development"   # development | ad-hoc | app-store | enterprise

usage() { sed -n '2,20p' "$0"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)     TEAM_ID="$2"; shift 2 ;;
    --unsigned) UNSIGNED=1; shift ;;
    --method)   METHOD="$2"; shift 2 ;;
    --config)   CONFIG="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) echo "Unknown option $1"; usage ;;
  esac
done

cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null; then
  echo "error: xcodebuild not found. Building an IPA requires macOS with Xcode." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"

echo "==> Archiving ($CONFIG)"
if [[ "$UNSIGNED" == "1" ]]; then
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_BITCODE=NO | xcpretty || true

  echo "==> Packaging unsigned IPA"
  PAYLOAD="$BUILD_DIR/Payload"
  rm -rf "$PAYLOAD"; mkdir -p "$PAYLOAD"
  cp -R "$ARCHIVE/Products/Applications/$SCHEME.app" "$PAYLOAD/"
  ( cd "$BUILD_DIR" && zip -qry "$SCHEME-unsigned.ipa" Payload )
  rm -rf "$PAYLOAD"
  echo "✅ $BUILD_DIR/$SCHEME-unsigned.ipa"
  echo "   Sideload it with AltStore / Sideloadly, or re-sign with your own certificate."
  exit 0
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "error: pass --team <APPLE_TEAM_ID> for a signed build, or use --unsigned." >&2
  exit 1
fi

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> Exporting IPA ($METHOD)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/ipa" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

echo "✅ IPA written to $BUILD_DIR/ipa/"
ls -lh "$BUILD_DIR/ipa/"*.ipa
