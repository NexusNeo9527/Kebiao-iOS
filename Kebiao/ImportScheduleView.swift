import SwiftUI
import UniformTypeIdentifiers

struct ImportScheduleView: View {
    let store: TimetableStore
    private let targetTimetableID: UUID
    private let originalTimetable: Timetable
    var onShowSchedule: (Date) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var isParsingFile = false
    @State private var preview: ScheduleImportPreview?
    @State private var errorMessage: String?
    @State private var pendingMode: TimetableStore.ImportMode?
    @State private var presentedSheet: ImportInputSheet?
    @State private var portalAddress = ""
    @State private var previewStyle: ImportPreviewStyle = .timetable
    @State private var completedImport: ScheduleImportPreview?
    @State private var completedMode: TimetableStore.ImportMode?
    @State private var completionFeedbackTrigger = 0

    init(store: TimetableStore, onShowSchedule: @escaping (Date) -> Void = { _ in }) {
        self.store = store
        self.onShowSchedule = onShowSchedule
        self.targetTimetableID = store.activeTimetableID
        self.originalTimetable = store.activeTimetable
    }

    private var targetTimetable: Timetable { store.timetable(id: targetTimetableID) ?? originalTimetable }

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let completedImport {
                            completionCard(completedImport)
                        } else {
                            if let preview { previewCard(preview) }
                            Text("导入至：\(targetTimetable.name)")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            introCard
                            portalLoginCard
                            supportedFormats
                        }
                    }
                    .id("import-result")
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .disabled(isParsingFile)
                .onChange(of: preview?.courses) { _, courses in
                    if courses != nil { scrollProxy.scrollTo("import-result", anchor: .top) }
                }
                .onChange(of: completedImport != nil) { _, _ in
                    scrollProxy.scrollTo("import-result", anchor: .top)
                }
                }
            }
            .navigationTitle("导入学校课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear(perform: migrateSavedPortalAddress)
            .sensoryFeedback(.success, trigger: completionFeedbackTrigger)
            .safeAreaInset(edge: .bottom) {
                if let preview, completedImport == nil {
                    importActions(preview)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .task {
                #if targetEnvironment(simulator)
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--ui-test-import-details") {
                    guard preview == nil, completedImport == nil else { return }
                    preview = Self.detailsTestPreview(in: targetTimetable)
                    previewStyle = .list
                } else if arguments.contains("--ui-test-import-preview") || arguments.contains("--ui-test-import-complete") {
                    guard preview == nil, completedImport == nil else { return }
                    preview = ScheduleImportPreview(sourceName: "示例课表.pdf", format: .pdf,
                                                     courses: Course.samples, warnings: [])
                    if arguments.contains("--ui-test-import-complete") { completeImport(.merge) }
                }
                #endif
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf, .commaSeparatedText, .json, .calendarEvent, .plainText, .html, .data]
            ) { result in
                switch result {
                case .success(let url):
                    parseImportedFile(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .overlay {
                if isParsingFile {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在解析课表…")
                            .font(.subheadline.weight(.semibold))
                        Text("扫描型 PDF 会在本机进行文字识别")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .paste:
                    PasteScheduleView(preview: $preview)
                case .portal(let url):
                    SchoolPortalLoginView(
                        url: url,
                        sourceName: url.host ?? "教务系统",
                        preview: $preview
                    )
                case .timetable(let imported):
                    NavigationStack {
                        ScheduleView(store: store, courses: imported.courses, timetable: targetTimetable,
                                     initialDate: previewDate(imported), showsNavigationBar: true)
                            .navigationTitle("课表预览")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("完成") { presentedSheet = nil }
                                }
                            }
                    }
                case .correction(let course):
                    ImportCourseCorrectionView(course: course, timetable: targetTimetable) { corrected in
                        guard let current = preview else { return }
                        preview = ScheduleImportPreview(sourceName: current.sourceName, format: current.format,
                            courses: current.courses.map { $0.id == corrected.id ? corrected : $0 },
                            warnings: current.warnings)
                        presentedSheet = nil
                    }
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .confirmationDialog("如何处理现有课程？", isPresented: Binding(
                get: { pendingMode != nil },
                set: { if !$0 { pendingMode = nil } }
            ), titleVisibility: .visible) {
                if pendingMode == .merge {
                    Button("合并导入，保留已有课程") { completeImport(.merge) }
                } else {
                    Button("替换全部课程", role: .destructive) { completeImport(.replace) }
                }
                Button("取消", role: .cancel) { pendingMode = nil }
            } message: {
                Text(pendingMode == .merge ? "完全相同的安排会去重，其他安排均会保留；同名课程不会自动合并。" : "现有课程将被本次导入内容替换。")
            }
        }
    }

    private var introCard: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.title2)
                        .foregroundStyle(KebiaoTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(KebiaoTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("从学校导入课表")
                            .font(.headline)
                        Text("输入学校教务网址，或选择课表文件导入")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("可以直接打开任意学校的教务系统读取当前课表，也可以导入 PDF、导出文件或复制表格。内容只在本机解析。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("选择文件", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        presentedSheet = .paste
                    } label: {
                        Label("粘贴课表", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .tint(KebiaoTheme.accent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var portalLoginCard: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("输入教务系统网址", systemImage: "person.badge.key.fill")
                    .font(.headline)
                Button("重庆理工大学 · 办事大厅") {
                    portalAddress = "https://ehall.cqut.edu.cn/new_office_hall/"
                }
                .buttonStyle(.bordered)
                TextField("教务系统网址，例如 https://jw.example.edu.cn", text: $portalAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(KebiaoTheme.background, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    if let portalURL {
                        portalAddress = portalURL.absoluteString
                        presentedSheet = .portal(portalURL)
                    }
                } label: {
                    Label("打开并登录", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(KebiaoTheme.accent)
                .disabled(portalURL == nil)
                Text("登录 → 进入教务系统 → 选择学年学期 → 打开完整个人课表 → 读取课表。重庆理工大学请从办事大厅进入教务系统；个人资料页不是课表。若学校限制访问，请使用校园网络。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var portalURL: URL? {
        let trimmed = portalAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }
        return Self.stablePortalEntry(from: components)
    }

    private func migrateSavedPortalAddress() {
        guard let savedAddress = UserDefaults.standard.string(forKey: "kebiao.school.portalURL") else { return }
        if let components = URLComponents(string: savedAddress),
           let stableURL = Self.stablePortalEntry(from: components) {
            portalAddress = stableURL.absoluteString
        }
        UserDefaults.standard.removeObject(forKey: "kebiao.school.portalURL")
    }

    static func stablePortalEntry(from original: URLComponents) -> URL? {
        var components = original
        let tokenNames: Set<String> = ["ticket", "code", "access_token", "id_token", "oauth_token"]
        let fragmentQuery = components.fragment?
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .first
        let fragmentItems = fragmentQuery.flatMap { query in
            URLComponents(string: "https://portal.invalid/?\(query)")?.queryItems
        } ?? []
        let hasOneTimeToken = ((components.queryItems ?? []) + fragmentItems)
            .contains { tokenNames.contains($0.name.lowercased()) }

        if hasOneTimeToken {
            // Preserve the application entry and SPA route, remove temporary
            // credentials from both the regular query and hash query.
            let removed = tokenNames.union(["state"])
            components.queryItems = components.queryItems?.filter { !removed.contains($0.name.lowercased()) }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            if let fragment = components.fragment, let separator = fragment.firstIndex(of: "?") {
                var query = URLComponents()
                query.queryItems = fragmentItems.filter { !removed.contains($0.name.lowercased()) }
                components.fragment = String(fragment[..<separator]) +
                    ((query.queryItems?.isEmpty == false) ? (query.query.map { "?" + $0 } ?? "") : "")
            }
        }
        return components.url
    }

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持格式")
                .font(.headline)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                formatBadge("CSV", detail: "教务表格", icon: "tablecells")
                formatBadge("PDF", detail: "文字或扫描课表", icon: "doc.richtext")
                formatBadge("ICS", detail: "日历课表", icon: "calendar")
                formatBadge("HTML/XLS", detail: "保存网页", icon: "safari")
                formatBadge("复制文本", detail: "网页或表格", icon: "doc.on.clipboard")
                formatBadge("JSON", detail: "结构化课表", icon: "curlybraces")
            }
        }
    }

    private func formatBadge(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(KebiaoTheme.accent)
            Text(title).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func previewCard(_ preview: ScheduleImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("导入预览")
                        .font(.headline)
                    Text("\(preview.sourceName) · \(preview.courses.count) 门课程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(preview.format.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(KebiaoTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(KebiaoTheme.accent.opacity(0.1), in: Capsule())
            }

            Label("解析完成，请核对课程后确认导入", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)

            Picker("预览方式", selection: $previewStyle) {
                Text("课表图").tag(ImportPreviewStyle.timetable)
                Text("课程明细").tag(ImportPreviewStyle.list)
            }
            .pickerStyle(.segmented)

            if previewStyle == .timetable {
                ScheduleView(store: store, courses: preview.courses, timetable: targetTimetable,
                             initialDate: previewDate(preview), showsNavigationBar: true)
                    .id(preview.courses)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    presentedSheet = .timetable(preview)
                } label: {
                    Label("展开课表预览", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Text("左右滑动查看整周，点击课程查看详情。预览内容尚未保存。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                previewCourseList(preview)
            }

            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }

    private func previewCourseList(_ preview: ScheduleImportPreview) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(preview.courses) { course in
                ImportPreviewCourseCard(course: course, timetable: targetTimetable, isPDF: preview.format == .pdf) {
                    presentedSheet = .correction(course)
                }
            }
        }
    }

    #if targetEnvironment(simulator)
    private static func detailsTestPreview(in timetable: Timetable) -> ScheduleImportPreview {
        let first = CourseTimeSlot(id: UUID(uuidString: "14100000-0000-0000-0000-000000000201")!,
            teacher: "王老师", location: "教学楼 A301", startSection: 4, sectionCount: 2,
            weekdays: [.monday, .friday], startWeek: 1, endWeek: 20,
            activeWeeks: [1, 2, 3, 5, 7, 8, 9, 11, 13, 14, 15, 17, 19, 20])
        let second = CourseTimeSlot(id: UUID(uuidString: "14100000-0000-0000-0000-000000000202")!,
            teacher: "李老师", location: "实验楼 B202", startSection: 7, weekdays: [.tuesday],
            startTimeMinutes: 23 * 60 + 30, startWeek: 2, endWeek: 6, activeWeeks: [2, 4, 6], durationMinutes: 120)
        let weekly = Course(id: UUID(uuidString: "14100000-0000-0000-0000-000000000101")!,
            name: "数据结构与算法设计（实验、讨论与跨专业综合实践）", colorValue: 0x5477D9,
            notes: "原始周次：1-3、5、7-9、11、13-15、17、19-20周；双周实验", timeSlots: [first, second])
        let calendar = timetable.calendar
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
        }
        let events = [
            DatedCourseEvent(id: UUID(uuidString: "14100000-0000-0000-0000-000000000301")!, startDate: date(14, 9), endDate: date(14, 10)),
            DatedCourseEvent(id: UUID(uuidString: "14100000-0000-0000-0000-000000000302")!, startDate: date(14, 15), endDate: date(14, 16)),
            DatedCourseEvent(id: UUID(uuidString: "14100000-0000-0000-0000-000000000303")!, startDate: date(14, 23, 30), endDate: date(15, 1, 30)),
            DatedCourseEvent(id: UUID(uuidString: "14100000-0000-0000-0000-000000000304")!, startDate: date(15, 15), endDate: date(15, 16))
        ]
        let dated = Course(id: UUID(uuidString: "14100000-0000-0000-0000-000000000102")!,
            name: "研讨与补课", colorValue: 0x3F9D80,
            timeSlots: [CourseTimeSlot(id: UUID(uuidString: "14100000-0000-0000-0000-000000000203")!,
                teacher: "赵老师", location: "综合楼 C303", datedEvents: events)])
        return ScheduleImportPreview(sourceName: "多时段校正示例.pdf", format: .pdf, courses: [weekly, dated], warnings: [])
    }
    #endif

    private func importActions(_ preview: ScheduleImportPreview) -> some View {
        HStack(spacing: 10) {
            Button("合并导入") { pendingMode = .merge }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(KebiaoTheme.accent)
            Button("替换现有") { pendingMode = .replace }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(preview.courses.isEmpty || isParsingFile || store.isReadOnly || store.timetable(id: targetTimetableID) == nil)
    }

    private func completeImport(_ mode: TimetableStore.ImportMode) {
        guard let preview, !preview.courses.isEmpty, completedImport == nil, !isParsingFile else { return }
        guard store.importCourses(preview.courses, mode: mode, into: targetTimetableID) else {
            errorMessage = store.errorMessage ?? "目标课表已被删除，课程未导入。"
            pendingMode = nil
            return
        }
        pendingMode = nil
        completedMode = mode
        completedImport = preview
        completionFeedbackTrigger += 1
    }

    private func previewDate(_ preview: ScheduleImportPreview) -> Date {
        preview.timetablePreviewDate(in: targetTimetable)
    }

    private func completionCard(_ imported: ScheduleImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("导入完成", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
                .accessibilityAddTraits(.isHeader)
            Text("已\(completedMode == .replace ? "替换导入" : "合并导入") \(imported.courses.count) 门课程")
                .font(.headline)
            Text("\(imported.sourceName) · \(targetTimetable.name) 共 \(targetTimetable.courses.count) 门课程")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(imported.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button {
                let date = previewDate(imported)
                store.selectTimetable(id: targetTimetableID)
                dismiss()
                onShowSchedule(date)
            } label: {
                Label("查看课表", systemImage: "calendar")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(KebiaoTheme.accent)

            Text("已保存的课表").font(.headline)
            ScheduleView(store: store, timetable: targetTimetable, initialDate: previewDate(imported), showsNavigationBar: true)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("继续导入其他课表") {
                completedImport = nil
                completedMode = nil
                preview = nil
                previewStyle = .timetable
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius))
    }

    private func parseImportedFile(_ url: URL) {
        isParsingFile = true
        preview = nil
        errorMessage = nil
        previewStyle = .timetable
        Task {
            do {
                let importedPreview = try await Task.detached(priority: .userInitiated) {
                    try ScheduleImportService.load(url: url)
                }.value
                preview = importedPreview
            } catch {
                errorMessage = error.localizedDescription
            }
            isParsingFile = false
        }
    }
}

private enum ImportInputSheet: Identifiable {
    case paste
    case portal(URL)
    case timetable(ScheduleImportPreview)
    case correction(Course)

    var id: String {
        switch self {
        case .paste: "paste"
        case .portal(let url): "portal-\(url.absoluteString)"
        case .timetable: "timetable-preview"
        case .correction(let course): "correction-\(course.id)"
        }
    }
}

private struct ImportCourseCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Course
    let timetable: Timetable
    let onSave: (Course) -> Void

    init(course: Course, timetable: Timetable, onSave: @escaping (Course) -> Void) {
        _draft = State(initialValue: course)
        self.timetable = timetable
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    KebiaoCard {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("课程名称", text: $draft.name).accessibilityIdentifier("import-correction-name")
                            Text("对照原课表校正星期、节次和周次。此处保存只更新预览，确认导入后才写入课表。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(draft.timeSlots.enumerated()), id: \.element.id) { index, slot in
                        CourseTimeSlotEditor(slot: Binding(get: {
                            draft.timeSlots.first { $0.id == slot.id } ?? slot
                        }, set: { value in
                            if let index = draft.timeSlots.firstIndex(where: { $0.id == slot.id }) { draft.timeSlots[index] = value }
                        }), number: index + 1, timetable: timetable)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("import-correction-slot-\(slot.id.uuidString)")
                    }
                }.padding(18)
            }.accessibilityIdentifier("import-correction-scroll")
                .background(KebiaoTheme.background.ignoresSafeArea())
                .navigationTitle("校正导入课程").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("import-correction-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { onSave(draft); dismiss() }.disabled(!CourseScheduleText.isValid(draft))
                            .accessibilityIdentifier("import-correction-save")
                    }
                }
        }
    }
}

private enum ImportPreviewStyle: Hashable {
    case timetable
    case list
}

private struct PasteScheduleView: View {
    @Binding var preview: ScheduleImportPreview?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("从教务系统课表页面复制完整表格，或复制每门课程的“课程名、教师、地点、上课时间”字段。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        TextEditor(text: $text)
                            .font(.body.monospaced())
                            .frame(minHeight: 300)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("在这里粘贴课表内容…")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 20)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("粘贴课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成预览") { parse() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法解析", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func parse() {
        do {
            preview = try ScheduleImportService.parseSchoolText(text, sourceName: "粘贴课表")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
