#!/bin/bash
# Builds the names spike into spike/build (gitignored), ad-hoc signed with the debugger entitlement
# (the same one the app carries) so task_for_pid works on the unhardened Hearthstone process.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/mod
swiftc -O -parse-as-library -emit-module -emit-library -static -module-name GameMemory \
  -emit-module-path build/mod/GameMemory.swiftmodule ../Sources/GameMemory/*.swift -o build/libGameMemory.a
swiftc -O -I build/mod names/main.swift build/libGameMemory.a -o build/names_spike
codesign -s - --entitlements ../packaging/HSBGMacOverlay.entitlements -f build/names_spike
echo built build/names_spike
