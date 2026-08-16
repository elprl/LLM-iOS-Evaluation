import Foundation
import SwiftData

/// A task persisted with SwiftData.
///
/// `@Model` classes are not `Sendable` and never cross actor boundaries here;
/// the `@ModelActor` maps them into the `Sendable` `TaskDTO` first.
@Model
final class TaskItem {
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String, isCompleted: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
