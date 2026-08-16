//
//  TaskDataActor.swift
//  TaskManager
//

import Foundation
import SwiftData

/// Owns a background `ModelContext` and performs every fetch and write off the main actor.
///
/// `@ModelActor` synthesises `init(modelContainer:)`, a `nonisolated let modelContainer`,
/// and an actor-isolated `modelContext` bound to this actor's executor. `ModelContainer`
/// itself is `Sendable`, so handing one over from the main actor is safe; the `ModelContext`
/// it creates never leaves this actor.
///
/// The methods below are synchronous *inside* the actor but satisfy ``TaskStore``'s `async`
/// requirements — Swift inserts the actor hop at the call site. Because every parameter and
/// return value is `Sendable`, none of those hops need `@unchecked` escape hatches.
@ModelActor
actor TaskDataActor: TaskStore {
    func tasks(matching query: TaskQuery) throws -> [TaskSnapshot] {
        let items = try modelContext.fetch(query.fetchDescriptor())
        // Convert to value types *before* returning: `TaskItem` is not `Sendable` and must
        // not escape this actor.
        return items.map(TaskSnapshot.init)
    }

    func count(matching query: TaskQuery) throws -> Int {
        try modelContext.fetchCount(query.fetchDescriptor())
    }

    func add(_ draft: TaskDraft) throws {
        let item = TaskItem(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: draft.dueDate,
            urgency: draft.urgency
        )

        modelContext.insert(item)
        try modelContext.save()
    }

    func setCompletion(_ isCompleted: Bool, forTaskWith id: PersistentIdentifier) throws {
        // `PersistentIdentifier` is `Sendable`, so it can travel; re-resolve it against this
        // actor's own context rather than passing the model across.
        guard let item = self[id, as: TaskItem.self] else { return }

        item.isCompleted = isCompleted
        try modelContext.save()
    }

    func delete(taskWith ids: [PersistentIdentifier]) throws {
        for id in ids {
            guard let item = self[id, as: TaskItem.self] else { continue }
            modelContext.delete(item)
        }

        try modelContext.save()
    }

    func seedSampleDataIfEmpty() throws {
        guard try modelContext.fetchCount(FetchDescriptor<TaskItem>()) == 0 else { return }

        let samples = [
            TaskItem(
                title: "Adopt Swift 6 strict concurrency",
                details: "Turn on complete checking and fix the fallout.",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                urgency: .high
            ),
            TaskItem(
                title: "Move fetches onto a ModelActor",
                details: "Keep the main actor free while querying.",
                dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
                urgency: .normal
            ),
            TaskItem(
                title: "Write snapshot types for the view layer",
                details: "Sendable value copies instead of PersistentModel.",
                urgency: .normal
            ),
            TaskItem(
                title: "Read the release notes",
                isCompleted: true,
                urgency: .low
            )
        ]

        for sample in samples {
            modelContext.insert(sample)
        }

        try modelContext.save()
    }
}
