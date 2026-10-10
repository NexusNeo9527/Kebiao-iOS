#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "WIDGET PACKAGE CHECK FAILED: $1" >&2
  exit 1
}

project_file="Kebiao.xcodeproj/project.pbxproj"
bundle_file="KebiaoWidget/KebiaoWidgetBundle.swift"
widget_file="KebiaoWidget/KebiaoTodayWidget.swift"
store_file="Kebiao/TimetableStore.swift"
group_id="group.com.example.kebiao"

grep -Fq 'KebiaoTodayWidget()' "$bundle_file" \
  || fail "the Home Screen widget is missing from the WidgetBundle"
grep -Fq 'KebiaoClassLiveActivity()' "$bundle_file" \
  || fail "the Live Activity is missing from the WidgetBundle"
grep -Fq 'StaticConfiguration(kind: kind, provider: TodayProvider())' "$widget_file" \
  || fail "the schedule widget has no static WidgetKit configuration"
grep -Fq '.supportedFamilies([.systemSmall, .systemMedium])' "$widget_file" \
  || fail "the schedule widget does not register its Home Screen sizes"
grep -Fq 'SharedTimetableReader' "$widget_file" \
  || fail "the widget does not use the shared timetable reader"
grep -Fq 'UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier)' Kebiao/SharedTimetableReader.swift \
  || fail "the shared reader does not read the App Group store"
grep -Fq 'UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier)' "$store_file" \
  || fail "the app does not write courses to the shared store"
grep -Fq 'WidgetCenter.shared.reloadAllTimelines()' "$store_file" \
  || fail "course changes do not request a widget refresh"
grep -Fq "static let appGroupIdentifier = \"$group_id\"" Kebiao/KebiaoConfiguration.swift \
  || fail "the Swift app-group identifier does not match the entitlement"

widget_sources=$(grep -F 'A30000000000000000000006 /* Sources */' "$project_file" || true)
[[ "$widget_sources" == *'A10000000000000000000009 /* KebiaoTodayWidget.swift in Sources */'* ]] \
  || fail "the widget source is not included in the extension target"
[[ "$widget_sources" == *'A10000000000000000000010 /* Models.swift in Sources */'* ]] \
  || fail "the extension target is missing the shared course model"
[[ "$widget_sources" == *'A10000000000000000000011 /* ScheduleEngine.swift in Sources */'* ]] \
  || fail "the extension target is missing active-week schedule rules"
for shared_source in SharedTimetableReader.swift TodayWidgetContent.swift; do
  [[ "$widget_sources" == *"$shared_source in Sources"* ]] \
    || fail "the extension target is missing $shared_source"
  app_sources=$(grep -F 'A30000000000000000000002 /* Sources */' "$project_file")
  [[ "$app_sources" == *"$shared_source in Sources"* ]] \
    || fail "the app target is missing $shared_source"
done
grep -Fq 'CODE_SIGN_ENTITLEMENTS = Kebiao/Kebiao.entitlements' "$project_file" \
  || fail "the app target is missing its App Group entitlements"
grep -Fq 'CODE_SIGN_ENTITLEMENTS = KebiaoWidget/KebiaoWidget.entitlements' "$project_file" \
  || fail "the widget target is missing its App Group entitlements"

for entitlement_file in Kebiao/Kebiao.entitlements KebiaoWidget/KebiaoWidget.entitlements; do
  [[ -f "$entitlement_file" ]] || fail "$entitlement_file is missing"
  grep -Fq '<string>'"$group_id"'</string>' "$entitlement_file" \
    || fail "$entitlement_file does not authorize $group_id"
done

if [[ $# -gt 0 ]]; then
  app_path="$1"
  extension_path="$app_path/PlugIns/KebiaoWidgetExtension.appex"
  [[ -d "$extension_path" ]] || fail "the WidgetKit extension is not embedded"

  app_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")
  extension_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_path/Info.plist")
  [[ "$extension_identifier" == "$app_identifier".* ]] \
    || fail "the extension bundle identifier is not prefixed by the app identifier"

  supports_live_activities=$(/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' "$app_path/Info.plist")
  [[ "$supports_live_activities" == "true" ]] || fail "NSSupportsLiveActivities is not enabled"

  extension_point=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$extension_path/Info.plist")
  [[ "$extension_point" == "com.apple.widgetkit-extension" ]] \
    || fail "the embedded extension is not a WidgetKit extension"
fi

echo "WIDGET PACKAGE CHECK PASSED: Home Screen widget and Live Activity are configured and embedded"
