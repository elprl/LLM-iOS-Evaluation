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
    let sharedModelContainer: ModelContainer
    @State private var viewModel: TaskListViewModel

    init() {
        let schema = Schema([
            TaskItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            let actor = TaskModelActor(modelContainer: container)
            _viewModel = State(initialValue: TaskListViewModel(modelActor: actor))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
