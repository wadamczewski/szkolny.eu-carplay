#!/bin/zsh
# Renderuje widgety na ciemnym tle w rozmiarze ekranu CarPlay (800×480 pt, PNG 1600×960) do
# docs/carplay/. Dane fikcyjne (tryb demo). To render widoków widgetów, nie zrzut z auta.
# Wymaga uruchomionego symulatora iOS. Użycie: ./scripts/carplay-preview.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null && xcodegen generate --quiet

xcodebuild \
  -project Dziennik.xcodeproj \
  -scheme Dziennik \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  -quiet build

PREFIX=$(awk -F'=' '/^BUNDLE_ID_PREFIX/ {gsub(/ /, "", $2); print $2}' Config/Signing.xcconfig)
APP_ID=$PREFIX.app
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Dziennik.app
xcrun simctl terminate booted "$APP_ID" 2>/dev/null || true
PNG="$(xcrun simctl get_app_container booted "$APP_ID" data)/Documents/carplay-widgety.png"
rm -f "$PNG"
xcrun simctl launch booted "$APP_ID" -DemoData -CarPlayPreview >/dev/null

for _ in {1..30}; do [[ -s $PNG ]] && break; sleep 1; done
[[ -s $PNG ]] || { echo "Brak $PNG" >&2; exit 1; }
mkdir -p docs/carplay
cp "$PNG" docs/carplay/widgety-carplay.png
echo docs/carplay/widgety-carplay.png
