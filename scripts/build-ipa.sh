#!/bin/zsh
# Buduje niepodpisany plik Dziennik.ipa do instalacji przez AltStore / SideStore
# (one same podpisują go Twoim Apple ID). Wymaga zainstalowanego Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null && xcodegen generate --quiet

xcodebuild \
  -project Dziennik.xcodeproj \
  -scheme Dziennik \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R build/DerivedData/Build/Products/Release-iphoneos/Dziennik.app build/ipa/Payload/
(cd build/ipa && zip -qry ../Dziennik.ipa Payload)
echo "Gotowe: $(pwd)/build/Dziennik.ipa"
