//
//  TaskListViewModel.swift
//  TaskManager
//
//  Created by Paul Leo on 04/09/2026.
//

import Foundation
import SwiftData
import Observation

/// The main UI ViewModel for the task list.
///
/// Features:
/// - Uses the modern `@Observable` macro for seamless observation in SwiftUI.
/// - Bound to `@MainActor` to safely drive SwiftUI view updates.
/// - Communicates with the background `TaskModelActor` exclusively via `async/await` and `Sendable` DTOs,
///   guaranteeing complete Swift 6 thread safety without any data races or Sendable warnings.
@Observable
@MainActor
final class TaskListViewModel {

    // MARK: - Published State

    var tasks: [TaskItemDTO] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var filter: TaskFilter = .all {
        didSet {
            Task { await loadTasks() }
        }
    }
    var sortBy: TaskSortOption = .createdAt {
        didSet {
            Task { await loadTasks() }
        }
    }
    var searchText: String = ""

    // MARK: - Filtered Presentation

    var displayedTasks: [TaskItemDTO] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tasks
        }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Dependencies

    private let modelActor: TaskModelActor

    // MARK: - Initialization

    init(modelActor: TaskModelActor) {
        self.modelActor = modelActor
    }

    // MARK: - Async Intent Methods

    /// Loads tasks asynchronously from the background actor.
    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Background query performed off the main thread by TaskModelActor
            let fetchedTasks = try await modelActor.fetchTasks(filter: filter, sortBy: sortBy)
            self.tasks = fetchedTasks
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    /// Pre-populates sample tasks if the database is currently empty.
    func seedInitialDataIfNeeded() async {
        do {
            try await modelActor.seedDefaultTasksIfNeeded()
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to seed sample data: \(error.localizedDescription)"
        }
    }

    /// Adds a new task in the background.
    func addTask(
        title: String,
        note: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            _ = try await modelActor.addTask(
                title: title,
                note: note,
                priority: priority,
                dueDate: dueDate
            )
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to add task: \(error.localizedDescription)"
        }
    }

    /// Toggles task completion status in the background.
    func toggleCompletion(for task: TaskItemDTO) async {
        // Optimistic local update for instantaneous UI feedback
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = TaskItemDTO(
                id: task.id,
                title: task.title,
                note: task.note,
                isCompleted: !task.isCompleted,
                priority: task.priority,
                dueDate: task.dueDate,
                createdAt: task.createdAt
            )
        }

        do {
            _ = try await modelActor.toggleTaskCompletion(id: task.id)
        } catch {
            // Revert on failure
            self.errorMessage = "Failed to update task: \(error.localizedDescription)"
            await loadTasks()
        }
    }

    /// Deletes tasks at specific index offsets within the currently displayed list.
    func delete(at offsets: IndexSet) async {
        let targets = offsets.map { displayedTasks[$0] }
        let idsToDelete = targets.map(\.id)

        // Optimistic UI removal
        tasks.removeAll(where: { idsToDelete.contains($0.id) })

        do {
            try await modelActor.deleteTasks(ids: idsToDelete)
        } catch {
            self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
            await loadTasks()
        }
    }

    /// Deletes a specific task.
    func delete(task: TaskItemDTO) async {
        tasks.removeAll(where: { $0.id == task.id })

        do {
            try await modelActor.deleteTask(id: task.id)
        } catch {
            self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
            await loadTasks()
        }
    }
}

// MARK: - Preview Factory

extension TaskListViewModel {
    static var preview: TaskListViewModel {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let actor = TaskModelActor(modelContainer: container)
        return TaskListViewModel(modelActor: actor)
    }
}
