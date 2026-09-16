import SwiftUI
import UniformTypeIdentifiers

struct ImportScheduleView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var preview: ScheduleImportPreview?
    @State private var errorMessage: String?
    @State private var pendingMode: TimetableStore.ImportMode?
    @State private var selectedPlatform: SchoolImportPlatform = .zhengfang
    @State private var presentedSheet: ImportInputSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introCard
                        platformPicker
                        importGuide
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
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.commaSeparatedText, .json, .calendarEvent, .plainText, .html, .data]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        preview = try ScheduleImportService.load(url: url)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .paste:
                    PasteScheduleView(platform: selectedPlatform, preview: $preview)
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
                        Text("文件、网页表格或复制文本都可以")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("选择你的教务系统，然后导入导出文件，或直接复制课表表格粘贴。全部在本机解析，不需要提交账号或密码。")
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

    private var platformPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择教务系统")
                .font(.headline)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SchoolImportPlatform.allCases) { platform in
                    Button {
                        withAnimation(.snappy) { selectedPlatform = platform }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: platform.icon)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.title).font(.subheadline.weight(.semibold))
                                Text(platform.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if selectedPlatform == platform {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(KebiaoTheme.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(13)
                        .background(
                            selectedPlatform == platform ? KebiaoTheme.accent.opacity(0.08) : .white,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(selectedPlatform == platform ? KebiaoTheme.accent.opacity(0.45) : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPlatform == platform ? .isSelected : [])
                }
            }
        }
    }

    private var importGuide: some View {
        KebiaoCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(selectedPlatform.title)导入方法", systemImage: "list.number")
                    .font(.headline)
                ForEach(Array(selectedPlatform.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(KebiaoTheme.accent, in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持格式")
                .font(.headline)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                formatBadge("CSV", detail: "教务表格", icon: "tablecells")
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

            ForEach(preview.courses.prefix(8)) { course in
                HStack(spacing: 10) {
                    Circle().fill(course.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(course.weekdays.sorted { $0.weekIndex < $1.weekIndex }.map(\.shortName).joined(separator: "、")) · 第\(course.startSection)–\(course.endSection)节")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if course.id != preview.courses.prefix(8).last?.id { Divider() }
            }

            if preview.courses.count > 8 {
                Text("另外还有 \(preview.courses.count - 8) 门课程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

enum SchoolImportPlatform: String, CaseIterable, Identifiable {
    case zhengfang
    case qiangzhi
    case qingguo
    case shuwei
    case generic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zhengfang: "正方教务"
        case .qiangzhi: "强智教务"
        case .qingguo: "青果教务"
        case .shuwei: "树维教务"
        case .generic: "其他学校"
        }
    }

    var subtitle: String {
        switch self {
        case .zhengfang: "常见新版/旧版"
        case .qiangzhi: "强智科技"
        case .qingguo: "青果软件"
        case .shuwei: "树维信息"
        case .generic: "通用表格"
        }
    }

    var icon: String {
        self == .generic ? "building.columns" : "graduationcap"
    }

    var steps: [String] {
        switch self {
        case .zhengfang:
            ["进入信息查询或学生课表查询。", "优先导出 CSV/Excel；没有导出按钮时，复制包含表头的课表表格。", "回到这里选择文件或粘贴课表，并确认预览。"]
        case .qiangzhi, .qingguo, .shuwei:
            ["登录学校教务系统并打开个人课表。", "导出 CSV/ICS/网页，或复制课程名称、教师、地点、上课时间等字段。", "回到这里导入；无法识别的行会单独提示，不会覆盖原课表。"]
        case .generic:
            ["在学校课表页面寻找导出、打印或保存网页。", "支持 CSV、ICS、HTML、文本及多数网页格式 XLS；也可直接复制表格。", "先检查本机预览，再选择合并或替换现有课程。"]
        }
    }
}

private enum ImportInputSheet: String, Identifiable {
    case paste
    var id: String { rawValue }
}

private struct PasteScheduleView: View {
    let platform: SchoolImportPlatform
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
                        Text("从 \(platform.title) 的课表页面复制完整表格，或复制每门课程的“课程名、教师、地点、上课时间”字段。")
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
            preview = try ScheduleImportService.parseSchoolText(text, sourceName: platform.title)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
