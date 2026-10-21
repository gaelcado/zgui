#!/bin/sh
# Build the terminal example as zterm.app (release), with its interface
# scripts inside, and install it: ./scripts/zterm-app.sh [destination]
# (default /Applications). Needs Zig 0.16 for Ghostty (see
# crates/zgui-ghostty-sys).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:-/Applications}
cd "$root"
cargo build --release -p zgui-desktop --features ghostty --example terminal

app="$dest/zterm.app"
staging=$(mktemp -d)/zterm.app
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources/terminal"
cp target/release/examples/terminal "$staging/Contents/MacOS/zterm"
# The interface: app.luau, its modules (in subdirectories too), its themes
# (.json) and .luaurc.
(cd crates/zgui-desktop/examples/terminal && find . -name '*.luau' -o -name '*.json' -o -name .luaurc) | while read -r file; do
  mkdir -p "$staging/Contents/Resources/terminal/$(dirname "$file")"
  cp "crates/zgui-desktop/examples/terminal/$file" "$staging/Contents/Resources/terminal/$file"
done
if [ -f scripts/zterm.icns ]; then
  cp scripts/zterm.icns "$staging/Contents/Resources/zterm.icns"
fi
cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>zterm</string>
  <key>CFBundleDisplayName</key><string>zterm</string>
  <key>CFBundleIdentifier</key><string>sh.zeron.zterm</string>
  <key>CFBundleExecutable</key><string>zterm</string>
  <key>CFBundleIconFile</key><string>zterm</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$staging" >/dev/null 2>&1 || true
rm -rf "$app"
mv "$staging" "$app"
echo "installed $app"
