//
//  TaskQuery.swift
//  TaskManager
//

import Foundation
import SwiftData

/// A fully-described, `Sendable` request for tasks.
///
/// This type is the reason the app avoids "sendability hell". `FetchDescriptor` is **not**
/// `Sendable`, so it can never be handed to ``TaskDataActor`` from the main actor. Instead
/// the view model sends this plain value across, and the actor turns it into a descriptor on
/// its own side, where the resulting non-`Sendable` machinery never has to move again.
///
/// It's also `Hashable`, which lets `TaskListView` drive re-fetches with `.task(id:)`.
nonisolated struct TaskQuery: Hashable, Sendable {
    var searchText: String = ""
    var filter: TaskFilter = .all
    var sortOrder: TaskSortOrder = .dueDate

    /// Built on the data actor's side, from `Sendable` captures only.
    func fetchDescriptor() -> FetchDescriptor<TaskItem> {
        FetchDescriptor(predicate: predicate(), sortBy: sortDescriptors())
    }

    private func predicate() -> Predicate<TaskItem> {
        // `#Predicate` can only capture simple values, so unpack everything up front.
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = search.isEmpty == false
        let requiresCompleted = filter == .completed
        let requiresActive = filter == .active

        return #Predicate<TaskItem> { item in
            (isSearching == false || item.title.localizedStandardContains(search))
                && (requiresCompleted == false || item.isCompleted)
                && (requiresActive == false || item.isCompleted == false)
        }
    }

    private func sortDescriptors() -> [SortDescriptor<TaskItem>] {
        switch sortOrder {
        case .dueDate:
            // Optional dates sort `nil` last, so undated tasks fall to the bottom.
            [SortDescriptor(\.dueDate), SortDescriptor(\.createdAt, order: .reverse)]
        case .urgency:
            [SortDescriptor(\.urgencyRawValue, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        case .created:
            [SortDescriptor(\.createdAt, order: .reverse)]
        case .title:
            [SortDescriptor(\.title)]
        }
    }
}
