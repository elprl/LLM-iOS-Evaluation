//
//  TaskListViewModel.swift
//  TaskManager
//

import Foundation
import Observation
import SwiftData

/// Main-actor view model for the task list.
///
/// It holds only `Sendable` value types (``TaskSnapshot``), never `TaskItem`, so nothing it
/// publishes to SwiftUI can be mutated behind the view's back by a background context.
///
/// The `@MainActor` annotation is redundant under this target's default-MainActor isolation,
/// but stating it makes the isolation contract obvious to a reader and keeps the type
/// correct if that build setting ever changes.
@MainActor
@Observable
final class TaskListViewModel {
    /// Where the list is in its load cycle. Drives the empty/error UI.
    enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var tasks: [TaskSnapshot] = []
    private(set) var state: LoadState = .idle

    var searchText = ""
    var filter: TaskFilter = .all
    var sortOrder: TaskSortOrder = .dueDate

    /// The error surfaced to the user, if any.
    private(set) var errorMessage: String?

    /// Bindable presentation flag for the error alert. Reading `errorMessage` in the getter
    /// is what registers the observation dependency, so this avoids a `Binding(get:set:)`
    /// in the view body.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if newValue == false { errorMessage = nil } }
    }

    /// The current request, recomputed from the user's choices. `TaskListView` feeds this to
    /// `.task(id:)`, so a change automatically cancels the in-flight fetch and starts a new
    /// one — which is also how search gets debounced, for free.
    var query: TaskQuery {
        TaskQuery(searchText: searchText, filter: filter, sortOrder: sortOrder)
    }

    var isEmpty: Bool {
        tasks.isEmpty && state == .loaded
    }

    private let store: any TaskStore

    init(store: any TaskStore) {
        self.store = store
    }

    /// Seeds sample data once, then performs the first fetch.
    func start() async {
        do {
            try await store.seedSampleDataIfEmpty()
        } catch {
            errorMessage = "Could not prepare the task store: \(error.localizedDescription)"
        }

        await load(query, debounce: false)
    }

    /// Fetches on the data actor. Safe to call repeatedly; `.task(id:)` cancels the previous
    /// call for us, and the debounce means fast typing only issues one real fetch.
    func load(_ query: TaskQuery, debounce: Bool = true) async {
        if debounce {
            // Cancellation throws here, which is exactly what we want: a superseded search
            // never reaches the store.
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
        }

        if state != .loaded { state = .loading }

        do {
            // The `await` is the actor hop. `query` goes over as a value; only value copies
            // come back.
            let snapshots = try await store.tasks(matching: query)
            guard Task.isCancelled == false else { return }

            tasks = snapshots
            state = .loaded
        } catch is CancellationError {
            // Superseded by a newer query — leave the existing results on screen.
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func addTask(_ draft: TaskDraft) async {
        guard draft.isValid else { return }

        await perform { try await $0.add(draft) }
    }

    func setCompletion(_ isCompleted: Bool, for task: TaskSnapshot) async {
        await perform { try await $0.setCompletion(isCompleted, forTaskWith: task.id) }
    }

    func delete(at offsets: IndexSet) async {
        let ids = offsets.map { tasks[$0].id }
        guard ids.isEmpty == false else { return }

        await perform { try await $0.delete(taskWith: ids) }
    }

    /// Runs a mutation on the data actor, then re-reads the list.
    ///
    /// The closure is `@Sendable` and takes the store as a parameter rather than capturing
    /// `self`, so no main-actor state is pulled across the boundary.
    private func perform(_ mutation: @Sendable (any TaskStore) async throws -> Void) async {
        do {
            try await mutation(store)
            await load(query, debounce: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
