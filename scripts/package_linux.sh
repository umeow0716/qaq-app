#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version-without-v> <release-tag>" >&2
  exit 2
fi

APP_NAME="QAQ"
APP_ID="dev.umeow.qaq"
PACKAGE_NAME="qaq"
APP_VERSION="$1"
RELEASE_TAG="$2"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Flutter includes the flavor in desktop output paths. Release builds use real
# explicitly, independently of the app's default beta flavor.
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/real/release/bundle"
DIST_DIR="$PROJECT_DIR/dist"
DESKTOP_FILE="$PROJECT_DIR/linux/packaging/$APP_ID.desktop"
ICON_FILE="$PROJECT_DIR/assets/images/desktop-icon.png"

if [[ ! -x "$BUNDLE_DIR/$APP_NAME" ]]; then
  echo "Linux release bundle not found: $BUNDLE_DIR/$APP_NAME" >&2
  exit 1
fi
if [[ ! -f "$DESKTOP_FILE" ]]; then
  echo "Desktop entry not found: $DESKTOP_FILE" >&2
  exit 1
fi
if [[ ! -f "$ICON_FILE" ]]; then
  echo "Desktop icon not found: $ICON_FILE" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Debian package -------------------------------------------------------------
DEB_ROOT="$(mktemp -d)"
APPIMAGE_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$DEB_ROOT" "$APPIMAGE_DIR"
}
trap cleanup EXIT

install -d \
  "$DEB_ROOT/DEBIAN" \
  "$DEB_ROOT/opt/qaq" \
  "$DEB_ROOT/usr/bin" \
  "$DEB_ROOT/usr/share/applications" \
  "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE_DIR/." "$DEB_ROOT/opt/qaq/"
ln -s /opt/qaq/QAQ "$DEB_ROOT/usr/bin/QAQ"
install -m 0644 "$DESKTOP_FILE" \
  "$DEB_ROOT/usr/share/applications/$APP_ID.desktop"
install -m 0644 "$ICON_FILE" \
  "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"

cat > "$DEB_ROOT/DEBIAN/control" <<EOF_CONTROL
Package: $PACKAGE_NAME
Version: $APP_VERSION
Section: education
Priority: optional
Architecture: amd64
Maintainer: QAQ Contributors <noreply@github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libwebkit2gtk-4.1-0, libsecret-1-0
Description: QAQ campus life assistant for NTUT students
 QAQ is an independent desktop and mobile campus life assistant.
EOF_CONTROL

DEB_OUTPUT="$DIST_DIR/$APP_NAME-$RELEASE_TAG-linux-amd64.deb"
dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_OUTPUT"

# AppImage -------------------------------------------------------------------
# Keep the Flutter bundle intact under usr/lib/qaq so the executable can still
# resolve its data/ and lib/ directories relative to itself.
install -d \
  "$APPIMAGE_DIR/usr/lib/qaq" \
  "$APPIMAGE_DIR/usr/bin" \
  "$APPIMAGE_DIR/usr/share/applications" \
  "$APPIMAGE_DIR/usr/share/icons/hicolor/512x512/apps"
cp -a "$BUNDLE_DIR/." "$APPIMAGE_DIR/usr/lib/qaq/"
ln -s ../lib/qaq/QAQ "$APPIMAGE_DIR/usr/bin/QAQ"
install -m 0644 "$DESKTOP_FILE" \
  "$APPIMAGE_DIR/usr/share/applications/$APP_ID.desktop"
install -m 0644 "$ICON_FILE" \
  "$APPIMAGE_DIR/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
install -m 0644 "$DESKTOP_FILE" "$APPIMAGE_DIR/$APP_ID.desktop"
install -m 0644 "$ICON_FILE" "$APPIMAGE_DIR/$APP_ID.png"
ln -s "$APP_ID.png" "$APPIMAGE_DIR/.DirIcon"

cat > "$APPIMAGE_DIR/AppRun" <<'EOF_APPRUN'
#!/bin/sh
set -eu
APPDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$APPDIR/usr/lib/qaq/QAQ" "$@"
EOF_APPRUN
chmod 0755 "$APPIMAGE_DIR/AppRun"

APPIMAGETOOL="$PROJECT_DIR/.dart_tool/appimagetool-x86_64.AppImage"
if [[ ! -x "$APPIMAGETOOL" ]]; then
  mkdir -p "$(dirname "$APPIMAGETOOL")"
  curl --fail --location --retry 3 \
    --output "$APPIMAGETOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
  chmod 0755 "$APPIMAGETOOL"
fi

APPIMAGE_OUTPUT="$DIST_DIR/$APP_NAME-$RELEASE_TAG-linux-x86_64.AppImage"
ARCH=x86_64 VERSION="$APP_VERSION" \
  "$APPIMAGETOOL" --appimage-extract-and-run \
  "$APPIMAGE_DIR" "$APPIMAGE_OUTPUT"
chmod 0755 "$APPIMAGE_OUTPUT"

printf 'Created:\n  %s\n  %s\n' "$DEB_OUTPUT" "$APPIMAGE_OUTPUT"
