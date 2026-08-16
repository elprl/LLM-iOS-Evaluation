import Foundation
import SwiftData

/// SwiftData persistence type. `nonisolated` opts this model out of the
/// module's default Main Actor isolation so a `@ModelActor` can use it
/// on its background executor without Sendable bridging.
@Model
nonisolated final class TaskItem {
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String, isCompleted: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
