import Foundation
import SwiftData

@ModelActor
actor TaskRepository {
    func fetchTasks() throws -> [TaskSnapshot] {
        let descriptor = FetchDescriptor<TaskEntity>(
            sortBy: [SortDescriptor(\TaskEntity.createdAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { task in
            TaskSnapshot(
                id: task.id,
                title: task.title,
                createdAt: task.createdAt,
                isCompleted: task.isCompleted
            )
        }
    }

    func addTask(title: String) throws -> [TaskSnapshot] {
        modelContext.insert(TaskEntity(title: title))
        try modelContext.save()
        return try fetchTasks()
    }

    func toggleTask(id: UUID) throws -> [TaskSnapshot] {
        let taskID = id
        var descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { task in
                task.id == taskID
            }
        )
        descriptor.fetchLimit = 1

        guard let task = try modelContext.fetch(descriptor).first else {
            throw TaskRepositoryError.taskNotFound
        }

        task.isCompleted.toggle()
        try modelContext.save()
        return try fetchTasks()
    }

    func deleteTasks(ids: [UUID]) throws -> [TaskSnapshot] {
        let identifiers = Set(ids)
        let storedTasks = try modelContext.fetch(FetchDescriptor<TaskEntity>())

        for task in storedTasks where identifiers.contains(task.id) {
            modelContext.delete(task)
        }

        try modelContext.save()
        return try fetchTasks()
    }
}
