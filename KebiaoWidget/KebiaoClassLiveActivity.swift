import ActivityKit
import SwiftUI
import WidgetKit

struct KebiaoClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("即将上课", systemImage: "bell.badge.fill")
                        .font(.headline)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Text(context.attributes.startDate, style: .time)
                        .font(.headline.monospacedDigit())
                }
                Text(context.attributes.courseName)
                    .font(.title2.bold())
                    .lineLimit(1)
                HStack {
                    Label(context.attributes.location, systemImage: "mappin.and.ellipse")
                    Spacer()
                    Text("第\(context.attributes.startSection)–\(context.attributes.endSection)节")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.12))
            .activitySystemActionForegroundColor(.indigo)
            .widgetURL(KebiaoConfiguration.scheduleURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startDate, style: .time)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.courseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.attributes.location, systemImage: "mappin")
                            .lineLimit(1)
                        Spacer()
                        Text("第\(context.attributes.startSection)–\(context.attributes.endSection)节")
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.indigo)
            } compactTrailing: {
                Text(context.attributes.startDate, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 42)
            } minimal: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.indigo)
            }
            .widgetURL(KebiaoConfiguration.scheduleURL)
            .keylineTint(.indigo)
        }
    }
}
