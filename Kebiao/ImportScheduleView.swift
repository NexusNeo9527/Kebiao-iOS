import SwiftUI
import UniformTypeIdentifiers

struct ImportScheduleView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var preview: ScheduleImportPreview?
    @State private var errorMessage: String?
    @State private var pendingMode: TimetableStore.ImportMode?

    var body: some View {
        NavigationStack {
            ZStack {
                KebiaoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introCard
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
                allowedContentTypes: [.commaSeparatedText, .json, .calendarEvent, .plainText]
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
                        Text("适配各学校导出文件")
                            .font(.headline)
                        Text("不需要提交教务系统账号或密码")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("先在学校教务系统中导出课表文件，再在这里选择。应用会在本机解析并显示预览，确认后才写入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    isImporterPresented = true
                } label: {
                    Label("选择课表文件", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(KebiaoTheme.accent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持格式")
                .font(.headline)
                .padding(.horizontal, 4)
            HStack(spacing: 10) {
                formatBadge("CSV", detail: "教务表格", icon: "tablecells")
                formatBadge("JSON", detail: "结构化课表", icon: "curlybraces")
                formatBadge("ICS", detail: "日历课表", icon: "calendar")
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
