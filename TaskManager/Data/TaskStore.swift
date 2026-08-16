//
//  TaskStore.swift
//  TaskManager
//

import Foundation
import SwiftData

/// The persistence surface the view model talks to.
///
/// Every parameter and return type here is `Sendable`, which is what makes the protocol
/// safe to call across actors. The conforming type (``TaskDataActor``) is an actor, so
/// conformance to `Sendable` comes for free and callers get `await` at each hop.
///
/// Keeping this a protocol also means tests — or previews — can swap in an in-memory
/// container without the view model knowing.
nonisolated protocol TaskStore: Sendable {
    /// Runs the fetch off the main actor and returns value copies.
    func tasks(matching query: TaskQuery) async throws -> [TaskSnapshot]

    /// Number of tasks matching the query, without materialising any models.
    func count(matching query: TaskQuery) async throws -> Int

    func add(_ draft: TaskDraft) async throws

    func setCompletion(_ isCompleted: Bool, forTaskWith id: PersistentIdentifier) async throws

    func delete(taskWith ids: [PersistentIdentifier]) async throws

    /// Inserts a small starter set the first time the app runs against an empty store.
    func seedSampleDataIfEmpty() async throws
}
