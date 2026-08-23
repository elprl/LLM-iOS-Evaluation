//
//  TaskModelActor.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import Foundation
import SwiftData

/// A background actor dedicated to SwiftData queries and persistence operations.
///
/// SwiftData's `@ModelActor` macro synthesizes a private `ModelContext` running on
/// a background executor. By doing all fetching, inserting, updating, and deleting
/// here, heavy database operations never block the MainActor / UI thread.
///
/// By returning Sendable `TaskDTO` structs (instead of `@Model` instances), this
/// actor cleanly avoids cross-actor data races and "sendability hell" under Swift 6.
@ModelActor
public actor TaskModelActor {

    /// Fetches tasks matching an optional predicate and sort order on a background thread.
    /// - Parameters:
    ///   - predicate: Optional SwiftData predicate for filtering.
    ///   - sortBy: Sort descriptors for ordering the results.
    /// - Returns: An array of Sendable `TaskDTO` objects.
    public func fetchTasks(
        predicate: Predicate<TaskItem>? = nil,
        sortBy: [SortDescriptor<TaskItem>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) throws -> [TaskDTO] {
        var descriptor = FetchDescriptor<TaskItem>(predicate: predicate, sortBy: sortBy)
        // Ensure faulting behavior doesn't trigger unexpected lazy loads across threads
        descriptor.includePendingChanges = true
        let items = try modelContext.fetch(descriptor)
        return items.map { TaskDTO(from: $0) }
    }

    /// Fetches a single task by its PersistentIdentifier.
    public func fetchTask(id: PersistentIdentifier) throws -> TaskDTO? {
        guard let item = modelContext.model(for: id) as? TaskItem else {
            return nil
        }
        return TaskDTO(from: item)
    }

    /// Creates and persists a new task on the background context.
    /// - Parameters:
    ///   - title: The title/description of the task.
    ///   - priority: The priority of the task.
    /// - Returns: The newly created `TaskDTO`.
    public func addTask(title: String, priority: TaskPriority = .medium) throws -> TaskDTO {
        let taskItem = TaskItem(title: title, isCompleted: false, createdAt: Date(), priority: priority)
        modelContext.insert(taskItem)
        try modelContext.save()
        return TaskDTO(from: taskItem)
    }

    /// Toggles the completion status of a task.
    /// - Parameter id: The PersistentIdentifier of the task.
    /// - Returns: The updated `TaskDTO`, or nil if not found.
    public func toggleTaskCompletion(id: PersistentIdentifier) throws -> TaskDTO? {
        guard let item = modelContext.model(for: id) as? TaskItem else {
            return nil
        }
        item.isCompleted.toggle()
        try modelContext.save()
        return TaskDTO(from: item)
    }

    /// Updates task details.
    public func updateTask(
        id: PersistentIdentifier,
        title: String? = nil,
        isCompleted: Bool? = nil,
        priority: TaskPriority? = nil
    ) throws -> TaskDTO? {
        guard let item = modelContext.model(for: id) as? TaskItem else {
            return nil
        }
        if let title {
            item.title = title
        }
        if let isCompleted {
            item.isCompleted = isCompleted
        }
        if let priority {
            item.priority = priority
        }
        try modelContext.save()
        return TaskDTO(from: item)
    }

    /// Deletes a task by its PersistentIdentifier.
    public func deleteTask(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? TaskItem else {
            return
        }
        modelContext.delete(item)
        try modelContext.save()
    }

    /// Deletes multiple tasks by their PersistentIdentifiers.
    public func deleteTasks(ids: [PersistentIdentifier]) throws {
        for id in ids {
            if let item = modelContext.model(for: id) as? TaskItem {
                modelContext.delete(item)
            }
        }
        try modelContext.save()
    }

    /// Seeds sample tasks if the database is currently empty.
    public func seedSampleTasksIfEmpty() throws {
        let descriptor = FetchDescriptor<TaskItem>()
        let count = try modelContext.fetchCount(descriptor)
        guard count == 0 else { return }

        let sampleData: [(title: String, priority: TaskPriority, isCompleted: Bool)] = [
            ("Adopt Swift 6 strict concurrency", .urgent, true),
            ("Build SwiftData background query with @ModelActor", .high, true),
            ("Implement Sendable DTO pattern to avoid Sendability hell", .high, true),
            ("Add unit tests using Swift Testing framework", .medium, false),
            ("Review SwiftUI @Observable MVVM data flow", .low, false)
        ]

        for sample in sampleData {
            let item = TaskItem(
                title: sample.title,
                isCompleted: sample.isCompleted,
                createdAt: Date().addingTimeInterval(Double.random(in: -86400 * 3 ... 0)),
                priority: sample.priority
            )
            modelContext.insert(item)
        }
        try modelContext.save()
    }

    /// Returns total number of tasks in the database.
    public func taskCount() throws -> Int {
        let descriptor = FetchDescriptor<TaskItem>()
        return try modelContext.fetchCount(descriptor)
    }
}
