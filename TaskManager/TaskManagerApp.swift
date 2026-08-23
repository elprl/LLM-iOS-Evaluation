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

    init() {
        do {
            let schema = Schema([
                TaskItem.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: sharedModelContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}
