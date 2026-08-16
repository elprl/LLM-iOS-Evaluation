//
//  TaskManagerApp.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import SwiftUI
import SwiftData

@main
struct TaskManagerApp: App {
    /// `ModelContainer` is `Sendable`, so the same instance can safely back both the SwiftUI
    /// environment and the background ``TaskDataActor``.
    private let modelContainer: ModelContainer

    /// Owned here with `@State` so the view model survives view identity changes.
    @State private var taskListViewModel: TaskListViewModel

    init() {
        let container = ModelContainerFactory.makeAppContainer()
        modelContainer = container
        _taskListViewModel = State(
            initialValue: TaskListViewModel(store: TaskDataActor(modelContainer: container))
        )
    }

    var body: some Scene {
        WindowGroup {
            TaskListView(viewModel: taskListViewModel)
        }
        .modelContainer(modelContainer)
    }
}
