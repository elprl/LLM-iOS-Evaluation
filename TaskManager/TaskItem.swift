//
//  TaskItem.swift
//  TaskManager
//
//  Created by Paul Leo on 04/09/2026.
//

import Foundation
import SwiftData

/// SwiftData PersistentModel representing a stored task.
///
/// NOTE: In Swift 6, `@Model` classes are non-Sendable reference types bound to a `ModelContext`.
/// They should NOT be passed across actor boundaries. Instead, perform operations within
/// the `@ModelActor` and transform into or out of `TaskItemDTO`.
@Model
public final class TaskItem {
    public var title: String
    public var note: String
    public var isCompleted: Bool
    public var priorityRaw: Int
    public var dueDate: Date?
    public var createdAt: Date

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    public init(
        title: String,
        note: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.note = note
        self.isCompleted = isCompleted
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.createdAt = createdAt
    }

    /// Converts this SwiftData entity into an immutable, Sendable DTO for cross-actor communication.
    public func toDTO() -> TaskItemDTO {
        TaskItemDTO(
            id: persistentModelID,
            title: title,
            note: note,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            createdAt: createdAt
        )
    }
}
