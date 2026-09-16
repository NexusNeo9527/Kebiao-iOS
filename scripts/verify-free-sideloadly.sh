#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FREE-SIGNING CHECK FAILED: $1" >&2
  exit 1
}

if grep -q 'com.apple.security.application-groups\|APP_GROUP_IDENTIFIER\|CODE_SIGN_ENTITLEMENTS' \
  Kebiao.xcodeproj/project.pbxproj Kebiao/Info.plist KebiaoWidget/Info.plist; then
  fail "the project still requests an App Group or entitlement file"
fi

if grep -q 'KebiaoTodayWidget()' KebiaoWidget/KebiaoWidgetBundle.swift; then
  fail "the App Group-dependent home-screen widget is still registered"
fi

grep -q 'KebiaoClassLiveActivity()' KebiaoWidget/KebiaoWidgetBundle.swift \
  || fail "the Live Activity is missing from the WidgetBundle"

grep -Fq 'Text(context.attributes.startDate, style: .time)' KebiaoWidget/KebiaoClassLiveActivity.swift \
  || fail "the Live Activity source is missing its class-time presentation"

grep -Fq 'context.attributes.location' KebiaoWidget/KebiaoClassLiveActivity.swift \
  || fail "the Live Activity source is missing its classroom presentation"

if grep -q 'UserDefaults(suiteName:' Kebiao/TimetableStore.swift; then
  fail "the app still stores courses in an App Group suite"
fi

grep -q 'defaults = .standard' Kebiao/TimetableStore.swift \
  || fail "the app is not using its local UserDefaults container"

if [[ $# -gt 0 ]]; then
  app_path="$1"
  extension_path="$app_path/PlugIns/KebiaoWidgetExtension.appex"
  [[ -d "$extension_path" ]] || fail "the Live Activity extension is not embedded"

  supports_live_activities=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$app_path/Info.plist")
  [[ "$supports_live_activities" == "true" ]] || fail "NSSupportsLiveActivities is not enabled"

  extension_point=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$extension_path/Info.plist")
  [[ "$extension_point" == "com.apple.widgetkit-extension" ]] \
    || fail "the embedded extension is not a WidgetKit extension"
fi

echo "FREE-SIGNING CHECK PASSED: Live Activity is embedded without App Group dependencies"
