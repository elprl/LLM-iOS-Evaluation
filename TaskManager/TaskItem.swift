//
//  TaskItem.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import Foundation
import SwiftData

public enum TaskPriority: String, Codable, CaseIterable, Sendable, Comparable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"

    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

@Model
public final class TaskItem {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var priorityRawValue: String

    public var priority: TaskPriority {
        get {
            TaskPriority(rawValue: priorityRawValue) ?? .medium
        }
        set {
            priorityRawValue = newValue.rawValue
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        priority: TaskPriority = .medium
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.priorityRawValue = priority.rawValue
    }
}
