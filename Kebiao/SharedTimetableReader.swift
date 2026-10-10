import Foundation
import CryptoKit

enum SharedTimetableReadState: Equatable {
    case ready
    case empty
    case notSynced
    case containerUnavailable
    case corrupt
    case unsupportedVersion(Int)

    var isReadable: Bool { self == .ready || self == .empty }
    var title: String {
        switch self {
        case .ready, .empty: return "课表数据可读取"
        case .notSynced: return "尚未同步课表"
        case .containerUnavailable: return "共享容器不可用"
        case .corrupt: return "课表数据损坏"
        case .unsupportedVersion(let version): return "不支持的数据版本（\(version)）"
        }
    }
}

enum SharedTimetableSource: String, Equatable {
    case collection = "多课表数据"
    case legacy = "兼容旧课表数据"
}

struct SharedTimetableSnapshot {
    let state: SharedTimetableReadState
    let collection: TimetableCollection?
    let updatedAt: Date?
    let source: SharedTimetableSource?
    let detail: String?

    init(state: SharedTimetableReadState, collection: TimetableCollection? = nil, updatedAt: Date? = nil,
         source: SharedTimetableSource? = nil, detail: String? = nil) {
        self.state = state; self.collection = collection; self.updatedAt = updatedAt
        self.source = source; self.detail = detail
    }
    var timetable: Timetable? { state.isReadable ? collection?.activeTimetable : nil }
}

struct TimetableSyncMetadata: Codable, Equatable {
    let version: Int
    let writtenAt: Date
    let dataSHA256: String

    init(data: Data, writtenAt: Date) {
        version = 1; self.writtenAt = writtenAt; dataSHA256 = Self.digest(data)
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func matches(_ data: Data) -> Bool {
        version == 1 && writtenAt.timeIntervalSince1970.isFinite && dataSHA256 == Self.digest(data)
    }
}

enum SharedTimetablePersistence {
    /// The sidecar describes the bytes actually stored, and is intentionally outside backups.
    static func write(_ data: Data, to defaults: UserDefaults, at date: Date = .now) throws {
        let metadata = TimetableSyncMetadata(data: data, writtenAt: date)
        let encodedMetadata = try JSONEncoder().encode(metadata)
        defaults.set(data, forKey: KebiaoConfiguration.collectionStorageKey)
        guard (defaults.object(forKey: KebiaoConfiguration.collectionStorageKey) as? Data) == data else {
            throw TimetableValidationError.invalid("课表数据未能写入共享存储。")
        }
        defaults.set(encodedMetadata, forKey: KebiaoConfiguration.syncMetadataKey)
    }
}

struct SharedTimetableReader {
    private struct VersionHeader: Decodable { let version: Int }
    private let defaults: UserDefaults?
    private let sharedContainerAvailable: Bool

    init(defaults: UserDefaults?, sharedContainerAvailable: Bool) {
        self.defaults = defaults; self.sharedContainerAvailable = sharedContainerAvailable
    }

    static func shared() -> SharedTimetableReader {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KebiaoConfiguration.appGroupIdentifier)
        let defaults = UserDefaults(suiteName: KebiaoConfiguration.appGroupIdentifier)
        return SharedTimetableReader(defaults: defaults, sharedContainerAvailable: container != nil)
    }

    func read() -> SharedTimetableSnapshot {
        guard sharedContainerAvailable, let defaults else {
            return SharedTimetableSnapshot(state: .containerUnavailable,
                detail: "App 与小组件需要可用的同一个 App Group 共享容器。")
        }
        // Presence must be checked separately: a present value of the wrong type is damaged v2 data.
        if let stored = defaults.object(forKey: KebiaoConfiguration.collectionStorageKey) {
            guard let data = stored as? Data else {
                return SharedTimetableSnapshot(state: .corrupt, detail: "多课表数据类型无效，原始资料已保留。")
            }
            return readCollection(data, defaults: defaults)
        }
        guard let legacyStored = defaults.object(forKey: KebiaoConfiguration.storageKey) else {
            return SharedTimetableSnapshot(state: .notSynced)
        }
        guard let legacyData = legacyStored as? Data else {
            return SharedTimetableSnapshot(state: .corrupt, detail: "旧课表数据类型无效，原始资料已保留。")
        }
        do {
            let courses = try JSONDecoder().decode([Course].self, from: legacyData)
            let timestamp = defaults.object(forKey: KebiaoConfiguration.semesterStartKey) as? Double
            let table = Timetable(name: "默认课表",
                semesterStartDate: timestamp.map { Date(timeIntervalSince1970: $0) } ?? ScheduleEngine.defaultSemesterStart(for: .now),
                weekCount: 30, courses: courses)
            let collection = TimetableCollection(timetables: [table], activeTimetableID: table.id)
            try collection.validate()
            return SharedTimetableSnapshot(state: courses.isEmpty ? .empty : .ready, collection: collection, source: .legacy)
        } catch {
            return SharedTimetableSnapshot(state: .corrupt, detail: "旧课表无法读取，原始资料已保留。\(error.localizedDescription)")
        }
    }

    private func readCollection(_ data: Data, defaults: UserDefaults) -> SharedTimetableSnapshot {
        do {
            let header = try JSONDecoder().decode(VersionHeader.self, from: data)
            guard header.version == 2 else { return SharedTimetableSnapshot(state: .unsupportedVersion(header.version)) }
            let collection = try JSONDecoder().decode(TimetableCollection.self, from: data)
            try collection.validate()
            let metadata = (defaults.object(forKey: KebiaoConfiguration.syncMetadataKey) as? Data)
                .flatMap { try? JSONDecoder().decode(TimetableSyncMetadata.self, from: $0) }
            let updatedAt = metadata.flatMap { $0.matches(data) ? $0.writtenAt : nil }
            return SharedTimetableSnapshot(state: collection.activeTimetable?.courses.isEmpty == true ? .empty : .ready,
                collection: collection, updatedAt: updatedAt, source: .collection)
        } catch {
            return SharedTimetableSnapshot(state: .corrupt, detail: "多课表无法读取，原始资料已保留。\(error.localizedDescription)")
        }
    }
}
