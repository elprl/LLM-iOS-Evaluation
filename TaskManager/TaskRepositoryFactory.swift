import SwiftData

nonisolated enum TaskRepositoryFactory {
    /// `@ModelActor` uses the executor on which it is created. Creating it from
    /// an explicitly concurrent function keeps all SwiftData work off MainActor.
    @concurrent
    static func make(modelContainer: ModelContainer) async -> TaskRepository {
        TaskRepository(modelContainer: modelContainer)
    }
}
