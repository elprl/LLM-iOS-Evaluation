import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TaskListViewModel {
    private(set) var tasks: [TaskSnapshot] = []
    private(set) var isLoading = false
    private(set) var isPerformingMutation = false
    private(set) var errorMessage = ""
    var isShowingError = false

    private let repositoryTask: Task<TaskRepository, Never>

    init(modelContainer: ModelContainer) {
        repositoryTask = Task {
            await TaskRepositoryFactory.make(modelContainer: modelContainer)
        }
    }

    func loadTasks() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let repository = await repositoryTask.value
            let fetchedTasks = try await repository.fetchTasks()
            try Task.checkCancellation()
            tasks = fetchedTasks
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    @discardableResult
    func addTask(title: String) async -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, beginMutation() else { return false }
        defer { isPerformingMutation = false }

        do {
            let repository = await repositoryTask.value
            tasks = try await repository.addTask(title: normalizedTitle)
            return true
        } catch {
            present(error)
            return false
        }
    }

    func toggleTask(id: UUID) async {
        guard beginMutation() else { return }
        defer { isPerformingMutation = false }

        do {
            let repository = await repositoryTask.value
            tasks = try await repository.toggleTask(id: id)
        } catch {
            present(error)
        }
    }

    func deleteTasks(ids: [UUID]) async {
        guard !ids.isEmpty, beginMutation() else { return }
        defer { isPerformingMutation = false }

        do {
            let repository = await repositoryTask.value
            tasks = try await repository.deleteTasks(ids: ids)
        } catch {
            present(error)
        }
    }

    func dismissError() {
        isShowingError = false
    }

    private func beginMutation() -> Bool {
        guard !isPerformingMutation else { return false }
        isPerformingMutation = true
        return true
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}
