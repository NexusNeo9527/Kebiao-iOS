import SwiftUI
import UniformTypeIdentifiers

private struct TimetableFileDocument: FileDocument {
    static var calendarType: UTType { UTType(filenameExtension: "ics") ?? .plainText }
    static var readableContentTypes: [UTType] { [.json, calendarType, .data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupExportView: View {
    let store: TimetableStore
    @Environment(\.dismiss) private var dismiss
    @State private var tableID: UUID
    @State private var start: Date
    @State private var end: Date
    @State private var importing = false
    @State private var exporting = false
    @State private var document: TimetableFileDocument?
    @State private var contentType = UTType.json
    @State private var filename = "课表备份.json"
    @State private var pendingBackup: TimetableCollection?
    @State private var confirmingReplacement = false
    @State private var confirmingSnapshot = false
    @State private var message: String?

    init(store: TimetableStore) {
        self.store = store
        let table = store.activeTimetable
        let first = Weekday.monday.date(inWeekContaining: table.semesterStartDate, calendar: table.calendar)
        _tableID = State(initialValue: table.id)
        _start = State(initialValue: first)
        _end = State(initialValue: table.calendar.date(byAdding: .day, value: table.weekCount * 7 - 1, to: first) ?? first)
    }
    private var table: Timetable? { store.timetable(id: tableID) }
    private var eventCount: Int {
        guard let table, end >= start, let until = table.calendar.date(byAdding: .day, value: 1, to: table.calendar.startOfDay(for: end)),
              (table.calendar.dateComponents([.day], from: start, to: until).day ?? 0) <= 732 else { return 0 }
        return ScheduleEngine.occurrences(in: table, from: table.calendar.startOfDay(for: start), to: until)
            .filter { $0.startDate >= table.calendar.startOfDay(for: start) && $0.startDate < until }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(store.timetables.count) 张课表 · \(store.timetables.reduce(0) { $0 + $1.courses.count }) 门课程")
                    Button("导出完整备份") { exportBackup() }.disabled(store.isReadOnly)
                        .accessibilityIdentifier("backup-export")
                    Button("选择备份文件恢复") { importing = true }.accessibilityIdentifier("backup-import")
                    if store.hasRecoverySnapshot { Button("恢复到上一次完整恢复前") { confirmingSnapshot = true } }
                    if store.isReadOnly, store.originalData != nil {
                        Button("导出保留的原始数据") {
                            if let data = store.originalData { prepare(data, type: .json, name: "课表原始数据.json") }
                        }
                    }
                } header: { Text("本地备份") } footer: {
                    Text("备份包含全部课表、作息、多时段和调停课记录。保存到“文件”后，可在另一台设备恢复。")
                }
                if let backup = pendingBackup {
                    Section("恢复预览") {
                        ForEach(backup.timetables) { table in
                            LabeledContent(table.name, value: "\(table.courses.count) 门 · \(table.weekCount) 周")
                        }
                        Button("作为新课表导入") { restore(replaceAll: false) }.disabled(store.isReadOnly)
                        Button("完整恢复并替换现有资料", role: .destructive) { confirmingReplacement = true }
                        Button("取消恢复", role: .cancel) { pendingBackup = nil }
                    }
                }
                if let table {
                    Section {
                        Text(table.name).font(.headline)
                        DatePicker("开始日期", selection: $start, displayedComponents: .date)
                        DatePicker("结束日期", selection: $end, displayedComponents: .date)
                        LabeledContent("将导出", value: "\(eventCount) 次课程")
                        Button("导出 ICS 日历文件") { exportCalendar(table) }.disabled(end < start || store.isReadOnly)
                            .accessibilityIdentifier("calendar-export")
                    } header: { Text("日历导出") } footer: {
                        Text("只导出所选日期范围内实际生效的课程，停课不导出，调课使用调整后的时间。日期范围外的安排保留在完整备份中。")
                    }.environment(\.timeZone, table.calendar.timeZone)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let error = store.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("备份与导出")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                pendingBackup = nil
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pendingBackup = try TimetableBackupService.decode(Data(contentsOf: url))
                    message = nil
                } catch { message = "无法读取备份：\(error.localizedDescription)" }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
                switch result {
                case .success: message = "文件已保存。"
                case .failure(let error): message = "保存失败：\(error.localizedDescription)"
                }
            }
            .alert("完整恢复这份备份？", isPresented: $confirmingReplacement) {
                Button("取消", role: .cancel) { }
                Button("完整恢复", role: .destructive) { restore(replaceAll: true) }
            } message: { Text("将替换所有课表。现有资料会保留为恢复前快照，之后可以撤销这次恢复。") }
            .alert("恢复上一次快照？", isPresented: $confirmingSnapshot) {
                Button("取消", role: .cancel) { }
                Button("恢复", role: .destructive) {
                    if store.restorePreviousSnapshot() { pendingBackup = nil; message = "已恢复到上一次快照。" }
                }
            }
        }
    }
    private func prepare(_ data: Data, type: UTType, name: String) {
        document = TimetableFileDocument(data: data); contentType = type; filename = name; exporting = true
    }
    private func exportBackup() {
        do { prepare(try TimetableBackupService.encode(store.collection), type: .json, name: "课表备份.json") }
        catch { message = error.localizedDescription }
    }
    private func exportCalendar(_ table: Timetable) {
        do { prepare(try TimetableBackupService.calendarData(timetable: table, from: start, through: end), type: TimetableFileDocument.calendarType, name: "课表日历.ics") }
        catch { message = error.localizedDescription }
    }
    private func restore(replaceAll: Bool) {
        guard let backup = pendingBackup else { return }
        if store.restoreBackup(backup, replaceAll: replaceAll) {
            pendingBackup = nil; tableID = store.activeTimetableID; message = "课表已恢复。"
            let table = store.activeTimetable
            start = Weekday.monday.date(inWeekContaining: table.semesterStartDate, calendar: table.calendar)
            end = table.calendar.date(byAdding: .day, value: table.weekCount * 7 - 1, to: start) ?? start
        }
    }
}
