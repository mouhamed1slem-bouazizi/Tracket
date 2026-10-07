#!/bin/sh
set -eu

PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build --disable-sandbox -c release --product Tracket
swift build --disable-sandbox -c release --product tracket-hook
swift build --disable-sandbox -c release --product tracket-local-ai
"$PROJECT_DIR/scripts/build-mlx-metallib.sh" release
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
cp "$BUILD_DIR/tracket-local-ai" "$CONTENTS_DIR/Helpers/tracket-local-ai"
cp "$BUILD_DIR/mlx.metallib" "$CONTENTS_DIR/Resources/mlx.metallib"
ln -s ../Resources/mlx.metallib "$CONTENTS_DIR/Helpers/mlx.metallib"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
for RESOURCE_BUNDLE in "$BUILD_DIR"/*.bundle; do
    if [ -d "$RESOURCE_BUNDLE" ]; then
        cp -R "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/"
    fi
done
if [ -n "${TRACKET_GITHUB_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketGitHubOAuthClientID $TRACKET_GITHUB_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${TRACKET_CLOUDFLARE_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketCloudflareOAuthClientID $TRACKET_CLOUDFLARE_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
if [ -n "${TRACKET_VERCEL_OAUTH_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :TracketVercelOAuthClientID $TRACKET_VERCEL_OAUTH_CLIENT_ID" "$CONTENTS_DIR/Info.plist"
fi
chmod -R u+w "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --sign "$SIGNING_IDENTITY" "$CONTENTS_DIR/Helpers/tracket-hook"
codesign --force --sign "$SIGNING_IDENTITY" "$CONTENTS_DIR/Helpers/tracket-local-ai"
codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ditto --norsrc --noextattr --noqtn --noacl "$APP_DIR" "$DIST_DIR/Tracket.app"
if xattr -p com.apple.FinderInfo "$DIST_DIR/Tracket.app" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$DIST_DIR/Tracket.app"
fi
codesign --verify --deep --strict --verbose=2 "$DIST_DIR/Tracket.app"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$DIST_DIR/Tracket.app" "$ZIP_PATH"

echo "$ZIP_PATH"
echo "Code signing identity: $SIGNING_IDENTITY"
