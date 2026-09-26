#!/usr/bin/env bash
#
# Builds EverClip.app from the SwiftPM executable.
#
# Requires a full Xcode toolchain (SwiftUI's macros aren't in the standalone
# Command Line Tools). Usage: Scripts/build-app.sh [debug|release]
#
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="EverClip"
VERSION="0.1.0"
BUILD_NUMBER="1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "==> Building ${APP_NAME} (${CONFIG})"
swift build -c "${CONFIG}" --product "${APP_NAME}"

BIN_DIR="$(swift build -c "${CONFIG}" --product "${APP_NAME}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Executable not found at ${BIN_PATH}" >&2
    exit 1
fi

APP="${ROOT}/build/${APP_NAME}.app"
echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_PATH}" "${APP}/Contents/MacOS/${APP_NAME}"

sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD_NUMBER}/" \
    packaging/Info.plist > "${APP}/Contents/Info.plist"

printf 'APPL????' > "${APP}/Contents/PkgInfo"

if [[ -f packaging/AppIcon.icns ]]; then
    cp packaging/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || echo "  (ad-hoc signing skipped)"

echo "OK: built ${APP}"
echo "Run it with: open \"${APP}\""
