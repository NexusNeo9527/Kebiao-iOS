import SwiftUI

enum WeekSwipeDecision {
    static func weekDelta(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        minimumDistance: CGFloat = 60
    ) -> Int? {
        let horizontal = translation.width
        let vertical = translation.height
        let projectedDistance = max(abs(horizontal), abs(predictedEndTranslation.width))
        guard projectedDistance >= minimumDistance,
              abs(horizontal) > abs(vertical) * 1.2 else {
            return nil
        }
        return horizontal < 0 ? 1 : -1
    }
}

struct ScheduleView: View {
    let store: TimetableStore
    private let previewCourses: [Course]?
    private let previewTimetable: Timetable?
    private let showsNavigationBar: Bool
    @State private var weekAnchor = Date.now
    @State private var presentedSheet: ScheduleSheet?
    @State private var weekDirection = 1
    private let timeColumnWidth: CGFloat = 46
    private let sectionHeight: CGFloat = 76

    init(store: TimetableStore, courses: [Course]? = nil, timetable: Timetable? = nil,
         initialDate: Date = .now, showsNavigationBar: Bool = false) {
        self.store = store; self.previewCourses = courses; self.previewTimetable = timetable
        self.showsNavigationBar = showsNavigationBar
        _weekAnchor = State(initialValue: initialDate)
    }
    private var table: Timetable {
        var value = previewTimetable.flatMap { store.timetable(id: $0.id) } ?? previewTimetable ?? store.activeTimetable
        if let previewCourses {
            value.courses = previewCourses
            let last = previewCourses.flatMap(\.timeSlots).map { $0.activeWeeks?.max() ?? $0.resolvedEndWeek }.max() ?? 1
            value.weekCount = min(30, max(value.weekCount, last))
        }
        return value
    }
    private var calendar: Calendar { table.calendar }
    private var isPreview: Bool { previewCourses != nil }
    private var sectionCount: Int { table.sectionPeriods.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                let dayWidth = max(96, (geometry.size.width - timeColumnWidth) / 7)
                ScrollViewReader { horizontalProxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            weekdayHeader
                            ScrollViewReader { verticalProxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    ZStack(alignment: .topLeading) {
                                        gridLines(dayWidth: dayWidth)
                                        sectionLabels
                                        courseBlocks(dayWidth: dayWidth)
                                    }.frame(height: CGFloat(sectionCount) * sectionHeight)
                                        .padding(.bottom, 24)
                                }
                                .onAppear {
                                    if showsNavigationBar { verticalProxy.scrollTo("section-\(firstVisibleSection)", anchor: .top) }
                                }
                            }
                        }.frame(width: timeColumnWidth + dayWidth * 7)
                            .onAppear {
                                if showsNavigationBar { horizontalProxy.scrollTo("day-\(firstVisibleDay.rawValue)", anchor: .center) }
                            }
                    }
                }
            }.id(weekPageID).clipped()
        }
        .background(KebiaoTheme.background.ignoresSafeArea())
        .navigationBarHidden(!showsNavigationBar)
        .onChange(of: store.activeTimetableID) { _, _ in
            guard previewTimetable == nil, !isPreview else { return }
            weekAnchor = .now
            presentedSheet = nil
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .management: TimetableManagementView(store: store)
            case .settings: TimetableSettingsView(store: store)
            case .backup: BackupExportView(store: store)
            case .group(let group):
                GroupOccurrenceSheet(group: group, store: store, timetable: table, isPreview: isPreview)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if !isPreview, previewTimetable == nil {
                HStack {
                    Menu {
                        ForEach(store.timetables) { timetable in
                            Button { store.selectTimetable(id: timetable.id) } label: {
                                if timetable.id == store.activeTimetableID { Label(timetable.name, systemImage: "checkmark") }
                                else { Text(timetable.name) }
                            }
                        }
                        Divider()
                        Button("管理课表", systemImage: "rectangle.stack") { presentedSheet = .management }
                        Button("课表设置", systemImage: "slider.horizontal.3") { presentedSheet = .settings }
                        Button("备份与导出", systemImage: "square.and.arrow.up") { presentedSheet = .backup }
                    } label: {
                        HStack(spacing: 6) {
                            Text(table.name).font(.headline).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }.foregroundStyle(.primary)
                    }.accessibilityLabel("切换或管理课表").accessibilityValue(table.name)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekNumber < 1 ? "学期未开始" : "第 \(weekNumber) 周").font(.title2.weight(.bold))
                    Text(weekRangeText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                headerButton("chevron.left", label: "上一周") { moveWeek(by: -1) }
                Button("今天") { withAnimation(.snappy) { weekAnchor = .now } }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                headerButton("chevron.right", label: "下一周") { moveWeek(by: 1) }
            }
        }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            Text("节").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: timeColumnWidth)
            ForEach(Weekday.allCases) { day in
                let date = day.date(inWeekContaining: weekAnchor, calendar: calendar)
                let today = calendar.isDateInToday(date)
                VStack(spacing: 3) {
                    Text(day.shortName.replacingOccurrences(of: "周", with: "")).font(.caption.weight(.semibold))
                    Text("\(calendar.component(.day, from: date))").font(.subheadline.weight(today ? .bold : .regular))
                        .frame(width: 28, height: 28).background(today ? Color.primary : .clear, in: Circle())
                        .foregroundStyle(today ? Color.white : Color.secondary)
                }.frame(maxWidth: .infinity).id("day-\(day.rawValue)")
                    .accessibilityElement(children: .combine).accessibilityLabel("\(day.fullName)，\(calendar.component(.day, from: date))日")
            }
        }.padding(.bottom, 8)
    }
    private var firstVisibleDay: Weekday {
        Weekday.allCases.first { !occurrences(on: $0).isEmpty } ?? .monday
    }
    private var firstVisibleSection: Int { occurrences(on: firstVisibleDay).map { $0.course.startSection }.min() ?? 1 }
    private func occurrences(on day: Weekday) -> [CourseOccurrence] {
        ScheduleEngine.occurrences(in: table, on: day.date(inWeekContaining: weekAnchor, calendar: calendar))
    }
    private func gridLines(dayWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...sectionCount, id: \.self) { row in
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: dayWidth * 7, height: 0.5)
                    .offset(x: timeColumnWidth, y: CGFloat(row) * sectionHeight)
            }
            ForEach(0...7, id: \.self) { column in
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 0.5, height: CGFloat(sectionCount) * sectionHeight)
                    .offset(x: timeColumnWidth + CGFloat(column) * dayWidth)
            }
        }
    }
    private var sectionLabels: some View {
        VStack(spacing: 0) {
            ForEach(table.sectionPeriods) { period in
                VStack(spacing: 3) {
                    Text("\(period.id)").font(.headline)
                    Text(String(format: "%02d:%02d", period.startMinutes / 60, period.startMinutes % 60))
                        .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }.padding(.top, 6).frame(width: timeColumnWidth, height: sectionHeight, alignment: .top)
                    .id("section-\(period.id)")
            }
        }
    }
    private func courseBlocks(dayWidth: CGFloat) -> some View {
        ForEach(Weekday.allCases) { day in
            ForEach(OccurrenceGroup.groups(occurrences(on: day), row: rowPosition)) { group in
                Button { presentedSheet = .group(group) } label: {
                    OccurrenceBlock(group: group, calendar: calendar)
                }.buttonStyle(.plain)
                    .frame(width: dayWidth - 6, height: max(32, (group.endRow - group.startRow) * sectionHeight - 6))
                    .offset(x: timeColumnWidth + CGFloat(day.weekIndex) * dayWidth + 3, y: group.startRow * sectionHeight + 3)
                    .accessibilityLabel(group.occurrences.map { $0.course.name }.joined(separator: "、"))
                    .accessibilityHint(group.occurrences.count > 1 ? "轻点查看全部重叠安排" : "轻点查看课程详情")
            }
        }
    }
    private func rowPosition(_ date: Date) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        for (index, period) in table.sectionPeriods.enumerated() {
            if minutes < period.startMinutes { return CGFloat(index) }
            if minutes <= period.endMinutes {
                return CGFloat(index) + CGFloat(minutes - period.startMinutes) / CGFloat(period.endMinutes - period.startMinutes)
            }
        }
        return max(0, CGFloat(sectionCount) - 0.5)
    }
    private func headerButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage).frame(width: 28, height: 30) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private var weekNumber: Int {
        ScheduleEngine.academicWeekNumber(for: weekAnchor, calendar: calendar, semesterStart: table.semesterStartDate)
    }
    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy/M/d"
        return "\(formatter.string(from: Weekday.monday.date(inWeekContaining: weekAnchor, calendar: calendar))) – \(formatter.string(from: Weekday.sunday.date(inWeekContaining: weekAnchor, calendar: calendar)))"
    }
    private func moveWeek(by value: Int) {
        weekDirection = value >= 0 ? 1 : -1
        withAnimation(.snappy) { weekAnchor = calendar.date(byAdding: .weekOfYear, value: value, to: weekAnchor) ?? weekAnchor }
    }
    private var weekPageID: Date { Weekday.monday.date(inWeekContaining: weekAnchor, calendar: calendar) }
}

private struct OccurrenceGroup: Identifiable {
    let occurrences: [CourseOccurrence]
    let startRow: CGFloat
    let endRow: CGFloat
    var id: String { occurrences.map(\.id).joined(separator: "|") }
    static func groups(_ occurrences: [CourseOccurrence], row: (Date) -> CGFloat) -> [Self] {
        let sorted = occurrences.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        var result: [Self] = []
        var pending: [CourseOccurrence] = []
        var start: CGFloat = 0
        var end: CGFloat = 0
        for occurrence in sorted {
            let first = row(occurrence.startDate)
            let last = max(first + 0.5, row(occurrence.endDate))
            if !pending.isEmpty, first >= end {
                result.append(Self(occurrences: pending, startRow: start, endRow: end)); pending = []
            }
            if pending.isEmpty { start = first; end = last }
            pending.append(occurrence); end = max(end, last)
        }
        if !pending.isEmpty { result.append(Self(occurrences: pending, startRow: start, endRow: end)) }
        return result
    }
}

private enum ScheduleSheet: Identifiable {
    case management, settings, backup, group(OccurrenceGroup)
    var id: String {
        switch self {
        case .management: "management"
        case .settings: "settings"
        case .backup: "backup"
        case .group(let value): value.id
        }
    }
}

private struct OccurrenceBlock: View {
    let group: OccurrenceGroup
    let calendar: Calendar
    private var course: Course { group.occurrences[0].course }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if group.occurrences.count > 1 {
                Text("\(group.occurrences.count)次重叠").font(.system(size: 12, weight: .bold))
                Text(group.occurrences.map { $0.course.name }.joined(separator: " / ")).font(.system(size: 12, weight: .medium)).lineLimit(4)
            } else {
                Text(course.name).font(.system(size: 12, weight: .bold)).lineLimit(3).layoutPriority(1)
                if group.endRow - group.startRow >= 1 {
                    Text(course.location.isEmpty ? "未填写地点" : "@ \(course.location)").font(.system(size: 10)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if group.endRow - group.startRow >= 1, let occurrence = group.occurrences.first {
                Text(timeText(occurrence)).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            }
        }.foregroundStyle(.white).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(group.occurrences.count > 1 ? KebiaoTheme.accent : course.color,
                in: RoundedRectangle(cornerRadius: 10)).clipped()
    }
    private func timeText(_ occurrence: CourseOccurrence) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; formatter.timeZone = calendar.timeZone
        return "\(formatter.string(from: occurrence.startDate))–\(formatter.string(from: occurrence.endDate))"
    }
}

private struct GroupOccurrenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: OccurrenceGroup
    let store: TimetableStore
    let timetable: Timetable
    let isPreview: Bool
    var body: some View {
        NavigationStack {
            if group.occurrences.count == 1, let occurrence = group.occurrences.first {
                CourseOccurrenceDetailView(occurrence: occurrence, store: store, timetable: timetable, isPreview: isPreview)
            } else {
                List(group.occurrences) { occurrence in
                    NavigationLink {
                        CourseOccurrenceDetailView(occurrence: occurrence, store: store, timetable: timetable, isPreview: isPreview)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(occurrence.course.name).font(.headline)
                            Text(occurrence.startDate, format: .dateTime.hour().minute())
                            Text(occurrence.course.location).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.navigationTitle("\(group.occurrences.count)次重叠安排")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }
        }.environment(\.calendar, timetable.calendar).environment(\.timeZone, timetable.calendar.timeZone)
    }
}

struct CourseOccurrenceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let occurrence: CourseOccurrence
    let store: TimetableStore
    let timetable: Timetable
    var isPreview = false
    @State private var destination: OccurrenceDetailDestination?
    private var course: Course { occurrence.course }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(course.name).font(.title2.weight(.bold))
                Divider()
                Label(occurrenceDateText, systemImage: "calendar")
                Label(timeRangeText, systemImage: "clock")
                Label("第\(course.startSection)–\(course.endSection)节", systemImage: "number")
                Label(course.location.isEmpty ? "未填写地点" : course.location, systemImage: "mappin.and.ellipse")
                Label(course.teacher.isEmpty ? "未填写教师" : course.teacher, systemImage: "person")
                if let slot = course.timeSlots.first {
                    Label(CourseScheduleText.weeks(for: slot), systemImage: "calendar.badge.clock")
                    Label(slot.reminderMinutesBefore.map { "提前 \($0) 分钟提醒" } ?? "未设置提醒", systemImage: "bell")
                }
                if let credits = course.credits { Label("\(credits.formatted()) 学分", systemImage: "star.circle") }
                if let notes = course.notes, !notes.isEmpty { Label(notes, systemImage: "note.text") }
                if !isPreview {
                    Divider()
                    Button("编辑整门课", systemImage: "pencil") { destination = .edit }
                        .buttonStyle(.bordered).disabled(store.isReadOnly)
                    Button("仅调整本次", systemImage: "calendar.badge.exclamationmark") { destination = .adjust }
                        .buttonStyle(.borderedProminent).tint(KebiaoTheme.accent).disabled(store.isReadOnly)
                    Text("停课、改时间或教室只影响这一次。补课可在整门课编辑中添加具体日期时段。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $destination) { value in
                switch value {
                case .edit:
                    CourseEditorView(course: store.timetable(id: occurrence.timetableID)?.courses.first { $0.id == course.id } ?? course,
                        store: store, timetable: timetable)
                case .adjust: OccurrenceAdjustmentView(store: store, occurrence: occurrence)
                }
            }
    }
    private var occurrenceDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timetable.calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: occurrence.startDate)
    }
    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.timeZone = timetable.calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: occurrence.startDate)
        if !timetable.calendar.isDate(occurrence.startDate, inSameDayAs: occurrence.endDate) {
            formatter.dateFormat = "M/d HH:mm"
        }
        return startText + "–" + formatter.string(from: occurrence.endDate)
    }
}
private enum OccurrenceDetailDestination: String, Identifiable {
    case edit, adjust
    var id: String { rawValue }
}

struct TimetableCourseGroup: Identifiable {
    let courses: [Course]
    var id: UUID { courses[0].id }
    var startSection: Int { courses.map(\.startSection).min() ?? 1 }
    var endSection: Int { courses.map(\.endSection).max() ?? 1 }

    static func groups(_ courses: [Course]) -> [Self] {
        let sorted = courses.sorted {
            if $0.startSection != $1.startSection { return $0.startSection < $1.startSection }
            if $0.endSection != $1.endSection { return $0.endSection < $1.endSection }
            return $0.id.uuidString < $1.id.uuidString
        }
        var result: [Self] = []
        var pending: [Course] = []
        var end = 0
        for course in sorted {
            if !pending.isEmpty && course.startSection > end {
                result.append(Self(courses: pending))
                pending = []
                end = 0
            }
            pending.append(course)
            end = max(end, course.endSection)
        }
        if !pending.isEmpty { result.append(Self(courses: pending)) }
        return result
    }
}
