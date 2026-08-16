import Foundation
import SwiftData

/// Immutable snapshot of a `TaskItem` that is safe to hop across actors.
/// `@Model` instances are not `Sendable`; this value type is the only
/// representation the UI and view model ever see.
nonisolated struct TaskDTO: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let isCompleted: Bool
    let createdAt: Date
}
