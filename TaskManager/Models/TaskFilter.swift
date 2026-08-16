//
//  TaskFilter.swift
//  TaskManager
//

import Foundation

/// Which subset of tasks the list should show.
nonisolated enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case completed

    var id: Self { self }

    var name: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .completed: "Done"
        }
    }
}
