//
//  TaskSnapshot.swift
//  TaskManager
//

import Foundation
import SwiftData

/// An immutable, `Sendable` value copy of a ``TaskItem``.
///
/// This is the type that crosses the actor boundary between ``TaskDataActor`` and the main
/// actor. `PersistentIdentifier` *is* `Sendable`, so it can be carried back to the data
/// actor later to re-resolve the real model — no `PersistentModel` ever escapes its context.
nonisolated struct TaskSnapshot: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let details: String
    let isCompleted: Bool
    let createdAt: Date
    let dueDate: Date?
    let urgency: TaskUrgency

    /// Called on whichever actor owns `item` — never with an item from another context.
    init(_ item: TaskItem) {
        self.id = item.persistentModelID
        self.title = item.title
        self.details = item.details
        self.isCompleted = item.isCompleted
        self.createdAt = item.createdAt
        self.dueDate = item.dueDate
        self.urgency = item.urgency
    }

    var isOverdue: Bool {
        guard let dueDate, isCompleted == false else { return false }
        return dueDate < .now
    }
}
