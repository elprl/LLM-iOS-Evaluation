//
//  TaskItemDTO.swift
//  TaskManager
//
//  Created by Paul Leo on 04/09/2026.
//

import Foundation
import SwiftData

/// Represents the priority level of a task.
/// Conforms to `Sendable` and `Identifiable` so it can be safely transferred across actor boundaries
/// and used directly in SwiftUI ForEach pickers.
public enum TaskPriority: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Filter options for listing tasks.
public enum TaskFilter: String, Sendable, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"

    public var id: String { rawValue }
}

/// Sort options for listing tasks.
public enum TaskSortOption: String, Sendable, CaseIterable, Identifiable {
    case createdAt = "Created"
    case priority = "Priority"
    case title = "Title"

    public var id: String { rawValue }
}

/// An immutable, Sendable Data Transfer Object (DTO) representing a `TaskItem`.
///
/// In Swift 6 strict concurrency, SwiftData `@Model` classes cannot be passed across
/// actor boundaries because they are reference types tied to a specific `ModelContext`.
/// `TaskItemDTO` bridges this boundary by copying model values into a value type,
/// using SwiftData's Sendable `PersistentIdentifier` as its stable identity.
public struct TaskItemDTO: Identifiable, Sendable, Hashable {
    public let id: PersistentIdentifier
    public let title: String
    public let note: String
    public let isCompleted: Bool
    public let priority: TaskPriority
    public let dueDate: Date?
    public let createdAt: Date

    public nonisolated init(
        id: PersistentIdentifier,
        title: String,
        note: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
    }
}
