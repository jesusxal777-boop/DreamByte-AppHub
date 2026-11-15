#!/usr/bin/env bash
# Packages the already-built .app into an unsigned .ipa.
#
# This does NOT sign anything. The resulting Payload/*.app has no code
# signature, so iOS will reject it until you sign it with your own certificate
# and provisioning profile.
#
# Usage (on macOS, after xcodebuild):
#   CONFIGURATION=Release bash tools/package_unsigned_ipa.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
PRODUCTS="$ROOT/App/build/Build/Products/${CONFIGURATION}-iphoneos"
DIST="$ROOT/dist"

if [[ ! -d "$PRODUCTS" ]]; then
    echo "error: build products not found at $PRODUCTS" >&2
    echo "Run xcodebuild first (see docs/GITHUB_BUILD.md)." >&2
    exit 1
fi

APP_PATH="$(/usr/bin/find "$PRODUCTS" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "error: no .app bundle inside $PRODUCTS" >&2
    exit 1
fi

APP_NAME="$(basename "$APP_PATH")"

rm -rf "$DIST"
mkdir -p "$DIST/Payload"
/usr/bin/ditto "$APP_PATH" "$DIST/Payload/$APP_NAME"

{
    echo "app: $APP_NAME"
    echo "configuration: $CONFIGURATION"
    echo "signed: no (unsigned payload)"
    echo "built_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "xcode: $(xcodebuild -version 2>/dev/null | head -1 || echo unknown)"
    echo "commit: ${GITHUB_SHA:-unknown}"
} > "$DIST/BUILD_INFO.txt"

(
    cd "$DIST"
    /usr/bin/zip -qry "DreamByteAppHub-unsigned.ipa" Payload BUILD_INFO.txt
)

echo "wrote $DIST/DreamByteAppHub-unsigned.ipa (unsigned)"
