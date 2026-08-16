import Foundation
import SwiftData

/// A plain, value-type snapshot of a `TaskItem`.
///
/// `TaskItem` is a non-`Sendable` reference type owned by a `ModelContext`, so
/// it cannot be returned from a `@ModelActor` to the main actor. `TaskDTO` is
/// the `Sendable` representation that safely crosses that boundary. `ForEach`
/// renders these, which is also why identity is `PersistentIdentifier`-based.
struct TaskDTO: Identifiable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let isCompleted: Bool
    let createdAt: Date

    init(from item: TaskItem) {
        self.id = item.persistentModelID
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.createdAt = item.createdAt
    }
}
