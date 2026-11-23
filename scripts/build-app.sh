#!/bin/sh
# 배포용 .app과 zip을 dist/에 만든다. 사용법: ./scripts/build-app.sh [버전]
# Apple 개발자 인증서가 없어 ad-hoc 서명만 한다. 받은 사람이 처음 열 때 macOS가 막는다(README의 설치 참고).
set -eu
cd "$(dirname "$0")/.."
version="${1:-0.1.0}"
app="dist/Chiikawa Desktop.app"

# 아키텍처별로 빌드해 lipo로 합친다(--arch를 여러 개 주는 방식은 Xcode가 있어야 한다).
bins=""
for arch in arm64 x86_64; do
  opts="-c release --triple $arch-apple-macosx14.0 --scratch-path .build/$arch"
  swift build $opts
  bins="$bins $(swift build $opts --show-bin-path)/ChiikawaDesktop"
done

rm -rf dist
mkdir -p "$app/Contents/MacOS"
lipo -create -output "$app/Contents/MacOS/ChiikawaDesktop" $bins
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ChiikawaDesktop</string>
  <key>CFBundleIdentifier</key><string>io.github.seungsimdang.chiikawadesktop</string>
  <key>CFBundleName</key><string>Chiikawa Desktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>비공식 팬메이드 (非公式・ファンメイド). 원작 권리자와 관계없음.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
ditto -c -k --keepParent "$app" "dist/ChiikawaDesktop-$version.zip"
echo "만듦: $app, dist/ChiikawaDesktop-$version.zip"
