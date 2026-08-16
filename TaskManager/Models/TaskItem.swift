//
//  TaskItem.swift
//  TaskManager
//

import Foundation
import SwiftData

/// The persisted task record.
///
/// Two concurrency details matter here:
///
/// 1. The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without an
///    explicit `nonisolated` this class would be implicitly `@MainActor` and
///    ``TaskDataActor`` could not touch it off the main actor.
/// 2. `PersistentModel` is **not** `Sendable`. Instances of this type must never leave the
///    actor that owns their `ModelContext` — ``TaskSnapshot`` is what crosses actor
///    boundaries instead. That single rule is what keeps this app out of "sendability hell".
@Model
nonisolated final class TaskItem {
    var title: String
    var details: String
    var isCompleted: Bool
    var createdAt: Date
    var dueDate: Date?

    /// Urgency is stored as its raw value so `#Predicate` and `SortDescriptor` can use it
    /// directly — SwiftData cannot sort on a computed or `Codable` enum property. Prefer
    /// ``urgency`` everywhere except in key paths handed to SwiftData.
    var urgencyRawValue: Int

    /// Computed properties are ignored by `@Model`, so this is a free convenience wrapper.
    var urgency: TaskUrgency {
        get { TaskUrgency(rawValue: urgencyRawValue) ?? .normal }
        set { urgencyRawValue = newValue.rawValue }
    }

    init(
        title: String,
        details: String = "",
        isCompleted: Bool = false,
        createdAt: Date = .now,
        dueDate: Date? = nil,
        urgency: TaskUrgency = .normal
    ) {
        self.title = title
        self.details = details
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.urgencyRawValue = urgency.rawValue
    }
}
