#!/bin/bash
# Builds the throwaway spike into spike/build (gitignored). Ad-hoc signed with the debugger entitlement
# (same one HSTracker.app carries) so task_for_pid can work on the unhardened Hearthstone process.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
clang++ -std=c++17 -fobjc-arc -arch arm64 tribe_spike.mm -framework Foundation -framework AppKit -o build/tribe_spike
cat > build/ent.plist <<'P'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.debugger</key><true/></dict></plist>
P
codesign -s - --entitlements build/ent.plist -f build/tribe_spike
echo built build/tribe_spike
