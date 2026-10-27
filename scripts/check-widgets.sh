#!/bin/zsh
# Sprawdza logikę widgetów (następna lekcja, numerek, terminarz) na fikcyjnych danych, bez Symulatora.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -o build/check-widgets Shared/WidgetSnapshot.swift WidgetsCheck/main.swift
build/check-widgets
