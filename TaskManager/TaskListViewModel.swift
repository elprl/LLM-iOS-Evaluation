import Foundation
import Observation
import SwiftData

/// Main-actor UI state. It never holds `@Model` instances — only `TaskDTO`
/// values returned from `TaskModelActor` — so actor hops stay Sendable.
@MainActor
@Observable
final class TaskListViewModel {
    private let taskActor: TaskModelActor

    var tasks: [TaskDTO] = []
    var isLoading = false
    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    init(modelContainer: ModelContainer) {
        taskActor = TaskModelActor(modelContainer: modelContainer)
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try await taskActor.fetchTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTask(title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            let task = try await taskActor.addTask(title: trimmedTitle)
            tasks.insert(task, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTasks(ids: [PersistentIdentifier]) async {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)

        do {
            try await taskActor.deleteTasks(ids: ids)
            tasks.removeAll { idSet.contains($0.id) }
        } catch {
            errorMessage = error.localizedDescription
            await loadTasks()
        }
    }

    func toggleTask(_ task: TaskDTO) async {
        do {
            guard let updated = try await taskActor.toggleTask(id: task.id),
                  let index = tasks.firstIndex(where: { $0.id == task.id })
            else { return }
            tasks[index] = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
