//
//  TaskDTO.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import Foundation
import SwiftData

/// A Sendable Data Transfer Object representing a task.
///
/// Marked `nonisolated` so it can be freely created and transferred across any actor boundaries
/// (from `TaskModelActor` to `@MainActor` ViewModel and SwiftUI Views) without Sendability issues.
nonisolated public struct TaskDTO: Identifiable, Sendable, Hashable, Equatable {
    public let id: PersistentIdentifier
    public let taskUUID: UUID
    public var title: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var priority: TaskPriority

    public init(
        id: PersistentIdentifier,
        taskUUID: UUID,
        title: String,
        isCompleted: Bool,
        createdAt: Date,
        priority: TaskPriority
    ) {
        self.id = id
        self.taskUUID = taskUUID
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.priority = priority
    }

    public init(from model: TaskItem) {
        self.id = model.persistentModelID
        self.taskUUID = model.id
        self.title = model.title
        self.isCompleted = model.isCompleted
        self.createdAt = model.createdAt
        self.priority = model.priority
    }
}
