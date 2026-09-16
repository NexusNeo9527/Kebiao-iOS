import ActivityKit
import SwiftUI
import WidgetKit

struct KebiaoClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("下节课", systemImage: "bell.badge.fill")
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
                    Label("下节课", systemImage: "bell.badge.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("上课时间")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.attributes.startDate, style: .time)
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
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
                HStack(spacing: 3) {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(.indigo)
                    Text(context.attributes.location)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(maxWidth: 58)
            } compactTrailing: {
                Text(context.attributes.startDate, style: .time)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.indigo)
            }
            .widgetURL(KebiaoConfiguration.scheduleURL)
            .keylineTint(.indigo)
        }
    }
}
