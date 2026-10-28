#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release "$@"
BIN_DIR=$(swift build -c release --show-bin-path "$@")
APP="$PWD/dist/Autocomplete.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Autocomplete" "$APP/Contents/MacOS/Autocomplete"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Autocomplete</string>
<key>CFBundleIdentifier</key><string>local.autocomplete.mac</string>
<key>CFBundleName</key><string>Autocomplete</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Use a persistent certificate when available. Ad-hoc signatures change identity per build.
SIGNING_IDENTITY="${AUTOCOMPLETE_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print "Ad-hoc build: macOS permission entries may need removing and re-adding after this rebuild."
fi
print "Built $APP"
