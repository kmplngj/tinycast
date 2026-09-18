#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

products=${1:?Pass the Debug build products directory}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/tinycast-configuration-runtime.XXXXXX")
identifier="com.tinycast.configuration-test.$(uuidgen | tr '[:upper:]' '[:lower:]')"
app="$fixture/Configuration Test.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$products/Tinycast Dev.app/Contents/MacOS/Tinycast Dev.debug.dylib" "$app/Contents/Frameworks/"
cp -R "$products/Tinycast Dev.app/Contents/Resources/" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleExecutable</key><string>ConfigurationTest</string>
<key>CFBundleName</key><string>Configuration Test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx26.0 \
    -I "$products" Tests/configuration-runtime-test.swift \
    "$app/Contents/Frameworks/Tinycast Dev.debug.dylib" \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    -o "$app/Contents/MacOS/ConfigurationTest"
codesign --force --deep --sign - "$app"
echo "Fixture app: $app"
"$app/Contents/MacOS/ConfigurationTest" "${2:-}"
