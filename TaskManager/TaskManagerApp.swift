import SwiftData
import SwiftUI

@main
struct TaskManagerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TaskItem.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: modelContainer)
        }
    }
}
