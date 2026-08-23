//
//  TaskListViewModel.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import Foundation
import SwiftUI
import SwiftData

/// Filter options for the task list.
public enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"

    public var id: String { rawValue }
}

/// Sort options for the task list.
public enum TaskSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst = "Newest"
    case oldestFirst = "Oldest"
    case priorityHighToLow = "Priority"
    case alphabetical = "Title"

    public var id: String { rawValue }
}

/// The MainActor-isolated ViewModel managing UI state and orchestrating background SwiftData queries.
///
/// Marked with `@Observable` (Observation framework) and `@MainActor` to ensure
/// all UI state mutations happen safely on the main thread while database operations
/// are asynchronously offloaded to `TaskModelActor`.
@MainActor
@Observable
public final class TaskListViewModel {
    // MARK: - Dependencies
    private let modelActor: TaskModelActor

    // MARK: - Observable State
    public var tasks: [TaskDTO] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var searchText: String = ""
    public var filter: TaskFilter = .all
    public var priorityFilter: TaskPriority? = nil
    public var sortOrder: TaskSortOrder = .newestFirst
    public var isShowingAddSheet: Bool = false

    // MARK: - Initializer
    public init(modelContainer: ModelContainer) {
        self.modelActor = TaskModelActor(modelContainer: modelContainer)
    }

    // MARK: - Computed Properties
    public var filteredTasks: [TaskDTO] {
        tasks
            .filter { task in
                // Status Filter
                switch filter {
                case .all:
                    break
                case .active:
                    if task.isCompleted { return false }
                case .completed:
                    if !task.isCompleted { return false }
                }

                // Priority Filter
                if let priorityFilter, task.priority != priorityFilter {
                    return false
                }

                // Search Filter
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !task.title.localizedCaseInsensitiveContains(searchText) {
                        return false
                    }
                }

                return true
            }
            .sorted { lhs, rhs in
                switch sortOrder {
                case .newestFirst:
                    return lhs.createdAt > rhs.createdAt
                case .oldestFirst:
                    return lhs.createdAt < rhs.createdAt
                case .priorityHighToLow:
                    if lhs.priority == rhs.priority {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.priority > rhs.priority
                case .alphabetical:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    public var activeTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    public var completedTaskCount: Int {
        tasks.filter { $0.isCompleted }.count
    }

    // MARK: - Actions (Async/Await)

    /// Loads tasks asynchronously from the background ModelActor.
    public func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Background query executed on TaskModelActor
            let fetched = try await modelActor.fetchTasks()
            self.tasks = fetched
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    /// Adds a new task using the background ModelActor and refreshes the list.
    public func addTask(title: String, priority: TaskPriority) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try await modelActor.addTask(title: trimmed, priority: priority)
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to add task: \(error.localizedDescription)"
        }
    }

    /// Toggles completion status of a task asynchronously.
    public func toggleTaskCompletion(_ task: TaskDTO) async {
        do {
            _ = try await modelActor.toggleTaskCompletion(id: task.id)
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }

    /// Deletes a specific task asynchronously.
    public func deleteTask(_ task: TaskDTO) async {
        do {
            try await modelActor.deleteTask(id: task.id)
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
        }
    }

    /// Deletes tasks at offsets from the filtered view.
    public func deleteTasks(at offsets: IndexSet) async {
        let targets = offsets.map { filteredTasks[$0] }
        let ids = targets.map(\.id)
        do {
            try await modelActor.deleteTasks(ids: ids)
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to delete tasks: \(error.localizedDescription)"
        }
    }

    /// Seeds sample data if empty and loads the list.
    public func seedSampleDataIfNeeded() async {
        do {
            try await modelActor.seedSampleTasksIfEmpty()
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to seed sample data: \(error.localizedDescription)"
        }
    }

    public func clearError() {
        self.errorMessage = nil
    }
}
