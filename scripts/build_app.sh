#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${BARO_VERSION:-1.2.1}"
cd "$ROOT_DIR"

echo "[1/5] Generating AppIcon.icns..."
python3 "$ROOT_DIR/scripts/generate_icon.py"

echo "[2/5] Building Baro v${VERSION} (Release)..."
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/Baro"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: release binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$ROOT_DIR/dist/Baro.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "[3/5] Assembling and stripping Baro.app..."
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Baro"
strip -x "$APP_DIR/Contents/MacOS/Baro"
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ROOT_DIR/dist/icon_build"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Baro</string>
    <key>CFBundleExecutable</key>
    <string>Baro</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.baro.monitor</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Baro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "[4/5] Ad-hoc signing Baro.app..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ZIP_NAME="Baro-v${VERSION}-macOS-arm64.zip"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_NAME"
SHA_PATH="$ROOT_DIR/dist/${ZIP_NAME}.sha256"

echo "[5/5] Creating distributable zip archive..."
rm -f "$ZIP_PATH" "$SHA_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "$ZIP_NAME" > "${ZIP_NAME}.sha256"
)

echo "Done! Release artifacts ready:"
echo "  - $APP_DIR"
echo "  - $ZIP_PATH"
echo "  - $SHA_PATH"
