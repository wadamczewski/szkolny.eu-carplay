#!/bin/zsh
# Buduje plik Dziennik.ipa do instalacji przez AltStore / SideStore (one same podpisują go
# Twoim Apple ID). Podpis ad hoc tylko przenosi uprawnienie App Group (dane dla widgetów),
# żeby AltStore/SideStore mogły je zarejestrować. Wymaga zainstalowanego Xcode.
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

APP=build/DerivedData/Build/Products/Release-iphoneos/Dziennik.app
# Ad hoc signature carrying the App Group entitlement (widget extension first, then the app).
PREFIX=$(awk -F'=' '/^BUNDLE_ID_PREFIX/ {gsub(/ /, "", $2); print $2}' Config/Signing.xcconfig)
ENTITLEMENTS=build/adhoc.entitlements
/usr/libexec/PlistBuddy -c "Clear dict" -c "Add :com.apple.security.application-groups array" \
  -c "Add :com.apple.security.application-groups:0 string group.$PREFIX" "$ENTITLEMENTS" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP/PlugIns/DziennikWidgets.appex"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../Dziennik.ipa Payload)
echo "Gotowe: $(pwd)/build/Dziennik.ipa"
