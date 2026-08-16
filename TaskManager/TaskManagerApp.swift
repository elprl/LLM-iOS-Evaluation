import SwiftData
import SwiftUI

@main
struct TaskManagerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(
                for: TaskEntity.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: modelContainer)
        }
        .modelContainer(modelContainer)
    }
}
