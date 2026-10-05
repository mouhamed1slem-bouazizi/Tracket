#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build --disable-sandbox -c release --product Tracket
swift build --disable-sandbox -c release --product tracket-hook
BUILD_DIR="$(cd "$PROJECT_DIR" && swift build --disable-sandbox -c release --show-bin-path)"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tracket-package.XXXXXX")"
APP_DIR="$STAGING_DIR/Tracket.app"
CONTENTS_DIR="$APP_DIR/Contents"
ZIP_PATH="$DIST_DIR/Tracket-macOS.zip"
SIGNING_IDENTITY="${TRACKET_CODESIGN_IDENTITY:-}"

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1)"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"
    echo "warning: no stable signing identity found; ad-hoc builds can be treated as new apps by Keychain and Privacy controls" >&2
fi

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

rm -rf "$DIST_DIR/Tracket.app"
rm -f "$ZIP_PATH"
mkdir -p "$DIST_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Helpers"
cp "$BUILD_DIR/Tracket" "$CONTENTS_DIR/MacOS/Tracket"
cp "$BUILD_DIR/tracket-hook" "$CONTENTS_DIR/Helpers/tracket-hook"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -n "${TRACKET_GITHUB_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketGitHubOAuthClientID $TRACKET_GITHUB_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${TRACKET_CLOUDFLARE_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketCloudflareOAuthClientID $TRACKET_CLOUDFLARE_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${TRACKET_VERCEL_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketVercelOAuthClientID $TRACKET_VERCEL_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
xattr -cr "$APP_DIR"
codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP_DIR" "$ZIP_PATH"

echo "$ZIP_PATH"
echo "Code signing identity: $SIGNING_IDENTITY"
