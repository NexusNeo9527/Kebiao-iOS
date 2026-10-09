import ActivityKit
import SwiftUI
import WidgetKit

struct KebiaoClassLiveActivity: Widget {
    private let islandAccent = Color.cyan

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("课程计时", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Text(context.attributes.startDate, style: .timer)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.indigo)
                }
                Text(context.attributes.courseName)
                    .font(.title2.bold())
                    .lineLimit(1)
                HStack {
                    Label(location(for: context.attributes), systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    Spacer()
                    Text("第\(context.attributes.startSection)–\(context.attributes.endSection)节")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack {
                    Text(context.attributes.startDate, style: .time)
                    Text("–")
                    Text(context.attributes.endDate, style: .time)
                    Spacer()
                    Text("课前倒计时 · 开课后计时")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.12))
            .activitySystemActionForegroundColor(.indigo)
            .widgetURL(KebiaoConfiguration.scheduleURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("课程", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(islandAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startDate, style: .timer)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.courseName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(location(for: context.attributes), systemImage: "mappin")
                                .lineLimit(1)
                            Spacer()
                            Text("第\(context.attributes.startSection)–\(context.attributes.endSection)节")
                        }
                        HStack {
                            Text(context.attributes.startDate, style: .time)
                            Text("–")
                            Text(context.attributes.endDate, style: .time)
                            Spacer()
                            Text("课前倒计时 · 开课后计时")
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .foregroundStyle(islandAccent)
                    Text(String(context.attributes.courseName.prefix(2)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                .frame(maxWidth: 42)
            } compactTrailing: {
                Text(context.attributes.startDate, style: .timer)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
            } minimal: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(islandAccent)
            }
            .widgetURL(KebiaoConfiguration.scheduleURL)
            .keylineTint(islandAccent)
        }
    }

    private func location(for attributes: ClassActivityAttributes) -> String {
        attributes.location.isEmpty ? "教室待定" : attributes.location
    }
}
