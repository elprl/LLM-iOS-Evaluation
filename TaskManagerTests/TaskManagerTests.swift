//
//  TaskManagerTests.swift
//  TaskManagerTests
//
//  Created by Paul Leo on 16/08/2026.
//

import Testing
import Foundation
import SwiftData
@testable import TaskManager

@Suite("TaskManager Swift 6 Concurrency & SwiftData Tests")
struct TaskManagerTests {

    /// Helper to create an in-memory ModelContainer for isolated testing.
    @MainActor
    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - TaskModelActor Tests

    @Test("TaskModelActor adds and fetches tasks in the background")
    func testModelActorAddAndFetch() async throws {
        let container = try await createTestModelContainer()
        let actor = TaskModelActor(modelContainer: container)

        // Initial state should be empty
        let initialTasks = try await actor.fetchTasks()
        #expect(initialTasks.isEmpty)

        // Add a task
        let added = try await actor.addTask(title: "Test Task 1", priority: .high)
        #expect(added.title == "Test Task 1")
        #expect(added.priority == .high)
        #expect(added.isCompleted == false)

        // Fetch back
        let fetchedTasks = try await actor.fetchTasks()
        #expect(fetchedTasks.count == 1)
        #expect(fetchedTasks.first?.title == "Test Task 1")
        #expect(fetchedTasks.first?.id == added.id)
    }

    @Test("TaskModelActor toggles task completion status")
    func testModelActorToggleCompletion() async throws {
        let container = try await createTestModelContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task = try await actor.addTask(title: "Toggle Me", priority: .medium)
        #expect(task.isCompleted == false)

        let toggled = try await actor.toggleTaskCompletion(id: task.id)
        #expect(toggled?.isCompleted == true)

        let fetched = try await actor.fetchTask(id: task.id)
        #expect(fetched?.isCompleted == true)

        let toggledBack = try await actor.toggleTaskCompletion(id: task.id)
        #expect(toggledBack?.isCompleted == false)
    }

    @Test("TaskModelActor deletes tasks")
    func testModelActorDelete() async throws {
        let container = try await createTestModelContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task1 = try await actor.addTask(title: "Task 1", priority: .low)
        let task2 = try await actor.addTask(title: "Task 2", priority: .urgent)

        #expect(try await actor.taskCount() == 2)

        try await actor.deleteTask(id: task1.id)
        #expect(try await actor.taskCount() == 1)

        let remaining = try await actor.fetchTasks()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == task2.id)
    }

    @Test("TaskModelActor seeds sample tasks when empty")
    func testModelActorSeedSampleTasks() async throws {
        let container = try await createTestModelContainer()
        let actor = TaskModelActor(modelContainer: container)

        try await actor.seedSampleTasksIfEmpty()
        let count = try await actor.taskCount()
        #expect(count == 5)

        // Calling it a second time should not duplicate tasks
        try await actor.seedSampleTasksIfEmpty()
        let countAfterSecondSeed = try await actor.taskCount()
        #expect(countAfterSecondSeed == 5)
    }

    // MARK: - TaskListViewModel Tests

    @Test("TaskListViewModel loads and manages tasks on MainActor")
    @MainActor
    func testViewModelLoadAndMutate() async throws {
        let container = try createTestModelContainer()
        let viewModel = TaskListViewModel(modelContainer: container)

        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.activeTaskCount == 0)

        // Add task via ViewModel
        await viewModel.addTask(title: "Learn Swift 6 Concurrency", priority: .urgent)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.activeTaskCount == 1)
        #expect(viewModel.completedTaskCount == 0)
        #expect(viewModel.errorMessage == nil)

        // Toggle task
        guard let firstTask = viewModel.tasks.first else {
            Issue.record("Expected task to exist")
            return
        }
        await viewModel.toggleTaskCompletion(firstTask)
        #expect(viewModel.tasks.first?.isCompleted == true)
        #expect(viewModel.activeTaskCount == 0)
        #expect(viewModel.completedTaskCount == 1)

        // Delete task
        await viewModel.deleteTask(viewModel.tasks[0])
        #expect(viewModel.tasks.isEmpty)
    }

    @Test("TaskListViewModel filtering and searching")
    @MainActor
    func testViewModelFilteringAndSearching() async throws {
        let container = try createTestModelContainer()
        let viewModel = TaskListViewModel(modelContainer: container)

        await viewModel.addTask(title: "Buy groceries", priority: .low)
        await viewModel.addTask(title: "Fix concurrency warning", priority: .urgent)
        await viewModel.addTask(title: "Write documentation", priority: .medium)

        #expect(viewModel.tasks.count == 3)

        // Mark one completed
        if let docTask = viewModel.tasks.first(where: { $0.title == "Write documentation" }) {
            await viewModel.toggleTaskCompletion(docTask)
        }

        // Test Filter: All
        viewModel.filter = .all
        #expect(viewModel.filteredTasks.count == 3)

        // Test Filter: Active
        viewModel.filter = .active
        #expect(viewModel.filteredTasks.count == 2)

        // Test Filter: Completed
        viewModel.filter = .completed
        #expect(viewModel.filteredTasks.count == 1)
        #expect(viewModel.filteredTasks.first?.title == "Write documentation")

        // Test Priority Filter
        viewModel.filter = .all
        viewModel.priorityFilter = .urgent
        #expect(viewModel.filteredTasks.count == 1)
        #expect(viewModel.filteredTasks.first?.title == "Fix concurrency warning")

        // Reset priority filter and test Search
        viewModel.priorityFilter = nil
        viewModel.searchText = "groceries"
        #expect(viewModel.filteredTasks.count == 1)
        #expect(viewModel.filteredTasks.first?.title == "Buy groceries")
    }

    @Test("TaskListViewModel sorting")
    @MainActor
    func testViewModelSorting() async throws {
        let container = try createTestModelContainer()
        let viewModel = TaskListViewModel(modelContainer: container)

        await viewModel.addTask(title: "Charlie", priority: .low)
        await viewModel.addTask(title: "Alpha", priority: .urgent)
        await viewModel.addTask(title: "Bravo", priority: .medium)

        // Alphabetical sort
        viewModel.sortOrder = .alphabetical
        let alphabeticalTitles = viewModel.filteredTasks.map(\.title)
        #expect(alphabeticalTitles == ["Alpha", "Bravo", "Charlie"])

        // Priority sort (Urgent > Medium > Low)
        viewModel.sortOrder = .priorityHighToLow
        let priorityOrder = viewModel.filteredTasks.map(\.priority)
        #expect(priorityOrder == [.urgent, .medium, .low])
    }
}
