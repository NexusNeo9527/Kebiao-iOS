import ActivityKit
import Foundation

struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let updatedAt: Date
    }

    let courseID: UUID
    let courseName: String
    let teacher: String
    let location: String
    let startSection: Int
    let endSection: Int
    let startDate: Date
    let endDate: Date
}
