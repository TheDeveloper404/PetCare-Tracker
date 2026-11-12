#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# An isolated simulator keeps automated tests away from personal simulator data.
verification_output="${VERIFY_OUTPUT:-$(mktemp -d /private/tmp/PetCareTracker-Verify.XXXXXX)}"
mkdir -p "$verification_output"
verification_device="${DEVICE_ID:-}"
verification_owns_device=false
if [[ -z "$verification_device" ]]; then
  xcrun simctl list devices available -j > "$verification_output/devices.json"
  read -r verification_runtime verification_type < <(python3 - "$verification_output/devices.json" <<'PY'
import json,sys,re
devices=json.load(open(sys.argv[1]))["devices"]
# UI assertions are verified against the compact iPhone 17 layout. Hardware-specific
# runtimes (for example iPhone Duo) can expose an adaptive toolbar instead of TabBar.
for runtime in sorted(devices, key=lambda x: tuple(map(int,re.findall(r"\d+",x))), reverse=True):
    for device in devices[runtime]:
        if device["name"] == "iPhone 17" and device.get("isAvailable",False):
            print(runtime,device["deviceTypeIdentifier"])
            sys.exit(0)
for runtime in sorted(devices, key=lambda x: tuple(map(int,re.findall(r"\d+",x))), reverse=True):
    for device in devices[runtime]:
        if device["name"].startswith("iPhone") and device.get("isAvailable",False):
            print(runtime,device["deviceTypeIdentifier"])
            sys.exit(0)
sys.exit("Install an iPhone simulator runtime in Xcode Settings > Components.")
PY
  )
  verification_device="$(xcrun simctl create "PetCare Verification $(uuidgen)" "$verification_type" "$verification_runtime")"
  verification_owns_device=true
fi
cleanup() {
  if [[ "$verification_owns_device" == true ]]; then
    xcrun simctl shutdown "$verification_device" >/dev/null 2>&1 || true
    xcrun simctl delete "$verification_device" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
xcrun simctl boot "$verification_device" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$verification_device" -b
xcrun simctl addmedia "$verification_device" PetCareTrackerUITests/Fixtures/TestPhoto-*.png
verification_arguments=(-project "PetCare Tracker.xcodeproj" -scheme "PetCare Tracker"
  -destination "platform=iOS Simulator,id=$verification_device" -derivedDataPath "$verification_output/DerivedData"
  -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 150)
xcodebuild "${verification_arguments[@]}" -configuration Debug -skip-testing:PetCareTrackerUITests test
verification_app="$verification_output/DerivedData/Build/Products/Debug-iphonesimulator/PetCare Tracker.app"
xcrun simctl install "$verification_device" "$verification_app"
export TEST_RUNNER_PETCARE_APP_BUNDLE_ID
TEST_RUNNER_PETCARE_APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$verification_app/Info.plist")
xcodebuild "${verification_arguments[@]}" -configuration Debug -only-testing:PetCareTrackerUITests test
xcodebuild "${verification_arguments[@]}" -configuration Release build analyze
echo "Verification artifacts: $verification_output"
