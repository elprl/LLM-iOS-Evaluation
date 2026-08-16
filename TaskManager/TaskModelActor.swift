import Foundation
import SwiftData

/// Serial SwiftData workhorse. `@ModelActor` gives this actor its own
/// `ModelContext` on a background executor, so fetches never block the UI.
@ModelActor
actor TaskModelActor {
    func fetchTasks() throws -> [TaskDTO] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(dto(from:))
    }

    func addTask(title: String) throws -> TaskDTO {
        let item = TaskItem(title: title)
        modelContext.insert(item)
        try modelContext.save()
        return dto(from: item)
    }

    func deleteTasks(ids: [PersistentIdentifier]) throws {
        for id in ids {
            guard let item = self[id, as: TaskItem.self] else { continue }
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    func toggleTask(id: PersistentIdentifier) throws -> TaskDTO? {
        guard let item = self[id, as: TaskItem.self] else { return nil }
        item.isCompleted.toggle()
        try modelContext.save()
        return dto(from: item)
    }

    private func dto(from item: TaskItem) -> TaskDTO {
        TaskDTO(
            id: item.persistentModelID,
            title: item.title,
            isCompleted: item.isCompleted,
            createdAt: item.createdAt
        )
    }
}
