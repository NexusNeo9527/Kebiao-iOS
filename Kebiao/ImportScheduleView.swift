import SwiftUI
import UniformTypeIdentifiers

struct ImportScheduleView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var isParsingFile = false
    @State private var preview: ScheduleImportPreview?
    @State private var errorMessage: String?
    @State private var pendingMode: TimetableStore.ImportMode?
    @State private var presentedSheet: ImportInputSheet?
    @State private var portalAddress = ""

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introCard
                        portalLoginCard
                        supportedFormats
                        if let preview { previewCard(preview) }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
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
                    Button("合并并更新重复课程") { completeImport(.merge) }
                } else {
                    Button("替换全部课程", role: .destructive) { completeImport(.replace) }
                }
                Button("取消", role: .cancel) { pendingMode = nil }
            } message: {
                Text(pendingMode == .merge ? "相同课程会更新，其余课程会保留。" : "现有课程将被本次导入内容替换。")
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
                Text("填写学校提供的固定入口网址。登录后打开个人课表，再点“读取当前课表”；账号和密码由学校网页处理。")
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

    private static func stablePortalEntry(from original: URLComponents) -> URL? {
        var components = original
        let tokenNames: Set<String> = ["ticket", "code", "access_token", "id_token", "oauth_token"]
        let fragmentQuery = components.fragment?
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .first
        let fragmentItems = fragmentQuery.flatMap { query in
            URLComponents(string: "https://portal.invalid/?\\(query)")?.queryItems
        } ?? []
        let hasOneTimeToken = ((components.queryItems ?? []) + fragmentItems)
            .contains { tokenNames.contains($0.name.lowercased()) }

        if hasOneTimeToken {
            components.path = "/"
            components.query = nil
            components.fragment = nil
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

            ForEach(preview.courses) { course in
                HStack(spacing: 10) {
                    Circle().fill(course.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(course.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: "、")) · 第\(course.startSection)–\(course.endSection)节")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if preview.format == .pdf {
                            Text(course.notes?.replacingOccurrences(of: "原始周次：", with: "周次：") ?? "周次待核对")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                if course.id != preview.courses.last?.id { Divider() }
            }

            ForEach(preview.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("合并导入") { pendingMode = .merge }
                    .buttonStyle(.borderedProminent)
                    .tint(KebiaoTheme.accent)
                Button("替换现有") { pendingMode = .replace }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .buttonBorderShape(.roundedRectangle(radius: 12))
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: KebiaoTheme.cardRadius, style: .continuous))
    }

    private func completeImport(_ mode: TimetableStore.ImportMode) {
        guard let preview else { return }
        store.importCourses(preview.courses, mode: mode)
        pendingMode = nil
        dismiss()
    }

    private func parseImportedFile(_ url: URL) {
        isParsingFile = true
        preview = nil
        errorMessage = nil
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

    var id: String {
        switch self {
        case .paste: "paste"
        case .portal(let url): "portal-\(url.absoluteString)"
        }
    }
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
