import Foundation
import SwiftData

/// Performs all SwiftData work off the main actor.
///
/// `@ModelActor` supplies a `modelContext` (backed by an executor the macro
/// creates) plus a `modelContainer`, and generates the initializer. We pass it
/// a `ModelContainer` — which *is* `Sendable` — rather than a `ModelContext`
/// (which is *not*), so nothing non-`Sendable` is handed across the actor
/// boundary.
@ModelActor
actor TaskModelActor {
    func fetchTasks() throws -> [TaskDTO] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let items = try modelContext.fetch(descriptor)
        // Map to Sendable DTOs *before* leaving the actor.
        return items.map { TaskDTO(from: $0) }
    }

    func addTask(title: String) throws {
        modelContext.insert(TaskItem(title: title))
        try modelContext.save()
    }

    func toggleTask(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? TaskItem else { return }
        item.isCompleted.toggle()
        try modelContext.save()
    }

    func deleteTask(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? TaskItem else { return }
        modelContext.delete(item)
        try modelContext.save()
    }
}
