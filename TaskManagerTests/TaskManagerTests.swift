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

@Suite("SwiftData Swift 6 Strict Concurrency Tests")
struct TaskManagerTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("TaskModelActor performs background insert and fetch safely")
    func testBackgroundInsertAndFetch() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        // Insert task via background actor
        let createdDTO = try await actor.addTask(
            title: "Test Task 1",
            note: "First note",
            priority: .high,
            dueDate: nil
        )

        #expect(createdDTO.title == "Test Task 1")
        #expect(createdDTO.note == "First note")
        #expect(createdDTO.priority == .high)
        #expect(createdDTO.isCompleted == false)

        // Fetch back from actor
        let allTasks = try await actor.fetchTasks(filter: .all, sortBy: .createdAt)
        #expect(allTasks.count == 1)
        #expect(allTasks.first?.id == createdDTO.id)
    }

    @Test("TaskModelActor toggles completion and filters tasks")
    func testToggleAndFiltering() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task1 = try await actor.addTask(title: "Task A", priority: .low)
        let task2 = try await actor.addTask(title: "Task B", priority: .medium)

        // Verify both pending
        var pending = try await actor.fetchTasks(filter: .pending)
        #expect(pending.count == 2)

        // Toggle task1
        let updatedTask1 = try await actor.toggleTaskCompletion(id: task1.id)
        #expect(updatedTask1?.isCompleted == true)

        // Check filtered queries
        pending = try await actor.fetchTasks(filter: .pending)
        #expect(pending.count == 1)
        #expect(pending.first?.id == task2.id)

        let completed = try await actor.fetchTasks(filter: .completed)
        #expect(completed.count == 1)
        #expect(completed.first?.id == task1.id)
    }

    @Test("TaskModelActor deletes tasks properly")
    func testDeletion() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task = try await actor.addTask(title: "To be deleted")
        var tasks = try await actor.fetchTasks(filter: .all)
        #expect(tasks.count == 1)

        try await actor.deleteTask(id: task.id)
        tasks = try await actor.fetchTasks(filter: .all)
        #expect(tasks.isEmpty)
    }

    @Test("TaskListViewModel coordinates with background actor on @MainActor")
    @MainActor
    func testViewModelIntegration() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)
        let viewModel = TaskListViewModel(modelActor: actor)

        #expect(viewModel.tasks.isEmpty)

        // Add task through ViewModel
        await viewModel.addTask(title: "ViewModel Task", note: "MVVM test", priority: .high)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "ViewModel Task")

        // Search text filtering
        viewModel.searchText = "ViewModel"
        #expect(viewModel.displayedTasks.count == 1)

        viewModel.searchText = "NonExistent"
        #expect(viewModel.displayedTasks.isEmpty)

        viewModel.searchText = ""

        // Toggle completion
        if let firstTask = viewModel.tasks.first {
            await viewModel.toggleCompletion(for: firstTask)
            #expect(viewModel.tasks.first?.isCompleted == true)
        }

        // Delete task
        if let firstTask = viewModel.tasks.first {
            await viewModel.delete(task: firstTask)
            #expect(viewModel.tasks.isEmpty)
        }
    }

    @Test("Concurrent actor operations execute without data races")
    func testConcurrentActorOperations() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        // Launch 20 concurrent tasks calling the background actor
        try await withThrowingTaskGroup(of: TaskItemDTO.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await actor.addTask(title: "Concurrent Task \(i)", priority: .medium)
                }
            }

            var count = 0
            for try await _ in group {
                count += 1
            }
            #expect(count == 20)
        }

        let allTasks = try await actor.fetchTasks(filter: .all)
        #expect(allTasks.count == 20)
    }
}
