//
//  TaskManagerTests.swift
//  TaskManagerTests
//
//  Created by Paul Leo on 16/08/2026.
//

import Foundation
import SwiftData
import Testing
@testable import TaskManager

/// Exercises the background data actor and the main-actor view model across the actor
/// boundary. Each test gets its own in-memory container so they can run in parallel.
struct TaskManagerTests {
    private func makeStore() -> TaskDataActor {
        TaskDataActor(modelContainer: ModelContainerFactory.makePreviewContainer())
    }

    @Test func addingATaskMakesItFetchable() async throws {
        let store = makeStore()
        try await store.add(TaskDraft(title: "Write the actor", urgency: .high))

        let tasks = try await store.tasks(matching: TaskQuery())

        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "Write the actor")
        #expect(tasks.first?.urgency == .high)
    }

    @Test func filterExcludesCompletedTasks() async throws {
        let store = makeStore()
        try await store.add(TaskDraft(title: "Done thing"))
        try await store.add(TaskDraft(title: "Pending thing"))

        let all = try await store.tasks(matching: TaskQuery())
        let doneID = try #require(all.first { $0.title == "Done thing" }?.id)
        try await store.setCompletion(true, forTaskWith: doneID)

        let active = try await store.tasks(matching: TaskQuery(filter: .active))
        let completed = try await store.tasks(matching: TaskQuery(filter: .completed))

        #expect(active.map(\.title) == ["Pending thing"])
        #expect(completed.map(\.title) == ["Done thing"])
    }

    @Test func searchMatchesCaseAndDiacriticInsensitively() async throws {
        let store = makeStore()
        try await store.add(TaskDraft(title: "Café renovation"))
        try await store.add(TaskDraft(title: "Buy milk"))

        let results = try await store.tasks(matching: TaskQuery(searchText: "cafe"))

        #expect(results.map(\.title) == ["Café renovation"])
    }

    @Test func urgencySortPutsHighestFirst() async throws {
        let store = makeStore()
        try await store.add(TaskDraft(title: "Low", urgency: .low))
        try await store.add(TaskDraft(title: "High", urgency: .high))
        try await store.add(TaskDraft(title: "Normal", urgency: .normal))

        let sorted = try await store.tasks(matching: TaskQuery(sortOrder: .urgency))

        #expect(sorted.map(\.title) == ["High", "Normal", "Low"])
    }

    @Test func deletingRemovesTheTask() async throws {
        let store = makeStore()
        try await store.add(TaskDraft(title: "Temporary"))

        let tasks = try await store.tasks(matching: TaskQuery())
        try await store.delete(taskWith: tasks.map(\.id))

        #expect(try await store.count(matching: TaskQuery()) == 0)
    }

    @Test func seedingOnlyHappensOnce() async throws {
        let store = makeStore()
        try await store.seedSampleDataIfEmpty()
        let afterFirstSeed = try await store.count(matching: TaskQuery())

        try await store.seedSampleDataIfEmpty()
        let afterSecondSeed = try await store.count(matching: TaskQuery())

        #expect(afterFirstSeed > 0)
        #expect(afterSecondSeed == afterFirstSeed)
    }

    @MainActor
    @Test func viewModelLoadsSnapshotsFromTheDataActor() async throws {
        let viewModel = TaskListViewModel(store: makeStore())
        await viewModel.start()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.tasks.isEmpty == false)

        // Mutating through the view model refreshes the published snapshots.
        await viewModel.addTask(TaskDraft(title: "Added via view model"))
        #expect(viewModel.tasks.contains { $0.title == "Added via view model" })
    }

    @MainActor
    @Test func viewModelRejectsBlankTitles() async throws {
        let viewModel = TaskListViewModel(store: makeStore())
        await viewModel.load(TaskQuery(), debounce: false)

        await viewModel.addTask(TaskDraft(title: "   "))

        #expect(viewModel.tasks.isEmpty)
    }
}
