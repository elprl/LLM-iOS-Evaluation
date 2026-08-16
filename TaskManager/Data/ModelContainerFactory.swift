//
//  ModelContainerFactory.swift
//  TaskManager
//

import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// `ModelContainer` is `Sendable`, so a single instance can be created here and handed to
/// both the main actor (for `@Query`/`modelContext` in SwiftUI) and ``TaskDataActor`` (which
/// makes its own private `ModelContext` from it). Sharing the *container* is fine; sharing a
/// `ModelContext` across actors is not.
nonisolated enum ModelContainerFactory {
    static let schema = Schema([TaskItem.self])

    static func makeAppContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the app's ModelContainer: \(error)")
        }
    }

    /// An ephemeral container for previews and tests.
    static func makePreviewContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create an in-memory ModelContainer: \(error)")
        }
    }
}
