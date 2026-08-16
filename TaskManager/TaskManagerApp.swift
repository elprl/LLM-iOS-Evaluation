import SwiftUI
import SwiftData

@main
@MainActor
struct TaskManagerApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: TaskListViewModel

    init() {
        let schema = Schema([TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.modelContainer = container
            self.viewModel = TaskListViewModel(container: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
