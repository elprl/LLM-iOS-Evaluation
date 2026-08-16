import Foundation
import Observation
import SwiftData

/// The "VM" in MVVM. Isolated to the main actor, it owns the `Sendable`
/// state the view renders and routes every mutation through
/// `TaskModelActor`.
///
/// Because the only state that crosses from the background actor is the
/// `Sendable` `[TaskDTO]`, no non-`Sendable` SwiftData object ever reaches
/// the UI — there is nothing to annotate or wrap to satisfy the compiler.
@MainActor
@Observable
final class TaskListViewModel {
    private(set) var tasks: [TaskDTO] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let store: TaskModelActor

    init(container: ModelContainer) {
        self.store = TaskModelActor(modelContainer: container)
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await store.fetchTasks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTask(_ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await store.addTask(title: trimmed)
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleTask(id: PersistentIdentifier) async {
        do {
            try await store.toggleTask(id: id)
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTasks(at offsets: IndexSet) async {
        do {
            let ids = offsets.map { tasks[$0].id }
            for id in ids {
                try await store.deleteTask(id: id)
            }
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
extension TaskListViewModel {
    /// A view model backed by an in-memory store, for Xcode previews.
    static func makePreview() -> TaskListViewModel {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return TaskListViewModel(container: container)
    }
}
