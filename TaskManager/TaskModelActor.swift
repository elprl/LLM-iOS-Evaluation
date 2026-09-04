//
//  TaskModelActor.swift
//  TaskManager
//
//  Created by Paul Leo on 04/09/2026.
//

import Foundation
import SwiftData

/// A background actor responsible for SwiftData persistence queries and mutations.
///
/// By using the `@ModelActor` macro, this actor provides safe, isolated background execution
/// with its own `ModelExecutor` and `ModelContext`.
///
/// To prevent Swift 6 strict concurrency data races, all methods return Sendable `TaskItemDTO`
/// instances instead of passing the non-Sendable `@Model TaskItem` reference type.
@ModelActor
actor TaskModelActor {

    /// Fetches tasks matching the specified filter and sort order in the background.
    /// - Parameters:
    ///   - filter: Filter criterion (`.all`, `.pending`, `.completed`).
    ///   - sortBy: Sort criterion (`.createdAt`, `.priority`, `.title`).
    /// - Returns: An array of Sendable `TaskItemDTO` value types safe to pass to `@MainActor`.
    public func fetchTasks(
        filter: TaskFilter = .all,
        sortBy: TaskSortOption = .createdAt
    ) throws -> [TaskItemDTO] {
        var descriptor: FetchDescriptor<TaskItem>

        switch filter {
        case .all:
            descriptor = FetchDescriptor<TaskItem>()
        case .pending:
            descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })
        case .completed:
            descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted })
        }

        switch sortBy {
        case .createdAt:
            descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        case .priority:
            descriptor.sortBy = [
                SortDescriptor(\.priorityRaw, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        case .title:
            descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        }

        let items = try modelContext.fetch(descriptor)
        return items.map { $0.toDTO() }
    }

    /// Inserts a new task in the background and saves the context.
    public func addTask(
        title: String,
        note: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) throws -> TaskItemDTO {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(
            title: trimmedTitle,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: false,
            priority: priority,
            dueDate: dueDate,
            createdAt: Date()
        )
        modelContext.insert(task)
        try modelContext.save()
        return task.toDTO()
    }

    /// Toggles the completion status of a task by its Sendable `PersistentIdentifier`.
    public func toggleTaskCompletion(id: PersistentIdentifier) throws -> TaskItemDTO? {
        guard let task = modelContext.model(for: id) as? TaskItem else {
            return nil
        }
        task.isCompleted.toggle()
        try modelContext.save()
        return task.toDTO()
    }

    /// Deletes a single task identified by its `PersistentIdentifier`.
    public func deleteTask(id: PersistentIdentifier) throws {
        if let task = modelContext.model(for: id) as? TaskItem {
            modelContext.delete(task)
            try modelContext.save()
        }
    }

    /// Deletes multiple tasks identified by their `PersistentIdentifier`s.
    public func deleteTasks(ids: [PersistentIdentifier]) throws {
        for id in ids {
            if let task = modelContext.model(for: id) as? TaskItem {
                modelContext.delete(task)
            }
        }
        try modelContext.save()
    }

    /// Seeds default sample tasks if the database is currently empty.
    public func seedDefaultTasksIfNeeded() throws {
        var descriptor = FetchDescriptor<TaskItem>()
        descriptor.fetchLimit = 1
        let count = try modelContext.fetchCount(descriptor)
        guard count == 0 else { return }

        let samples: [(String, String, TaskPriority, Date?)] = [
            (
                "Adopt Swift 6 Strict Concurrency",
                "Audit cross-actor boundaries and ensure Sendable conformance.",
                .high,
                Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ),
            (
                "Implement @ModelActor background worker",
                "Execute SwiftData fetch descriptors off the main thread.",
                .high,
                Calendar.current.date(byAdding: .day, value: 2, to: Date())
            ),
            (
                "Build modern @Observable ViewModel",
                "Bind UI state to MainActor with clean async/await interactions.",
                .medium,
                Calendar.current.date(byAdding: .day, value: 3, to: Date())
            ),
            (
                "Write Swift Testing verification suite",
                "Test background CRUD and Sendable DTO serialization.",
                .low,
                nil
            )
        ]

        for sample in samples {
            let task = TaskItem(
                title: sample.0,
                note: sample.1,
                isCompleted: false,
                priority: sample.2,
                dueDate: sample.3,
                createdAt: Date()
            )
            modelContext.insert(task)
        }
        try modelContext.save()
    }
}
