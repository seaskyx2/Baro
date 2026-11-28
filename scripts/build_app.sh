#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${BARO_VERSION:-1.4.2}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: invalid BARO_VERSION '$VERSION' (expected strict SemVer such as 1.4.2)" >&2
  exit 1
fi

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

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
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
    <string>0.0.0</string>
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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_DIR/Contents/Info.plist"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

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

ZIP_SHA256="$(awk '{print $1}' "$SHA_PATH")"
CASK_FILE="$ROOT_DIR/packaging/homebrew/baro.rb"
if [[ -f "$CASK_FILE" && "$ZIP_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  VERSION="$VERSION" ZIP_SHA256="$ZIP_SHA256" CASK_FILE="$CASK_FILE" python3 - << 'PY'
import os, pathlib, re

cask_path = pathlib.Path(os.environ["CASK_FILE"])
text = cask_path.read_text(encoding="utf-8")
text = re.sub(r'(^\s*version\s+)"[^"]+"', rf'\1"{os.environ["VERSION"]}"', text, count=1, flags=re.MULTILINE)
text = re.sub(r'(^\s*sha256\s+)(:no_check|"[^"]+")', rf'\1"{os.environ["ZIP_SHA256"]}"', text, count=1, flags=re.MULTILINE)
cask_path.write_text(text, encoding="utf-8")
PY
fi

echo "Done! Release artifacts ready:"
echo "  - $APP_DIR"
echo "  - $ZIP_PATH"
echo "  - $SHA_PATH"
