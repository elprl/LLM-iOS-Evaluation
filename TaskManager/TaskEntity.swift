import Foundation
import SwiftData

@Model
nonisolated final class TaskEntity {
    var id: UUID
    var title: String
    var createdAt: Date
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isCompleted = isCompleted
    }
}
