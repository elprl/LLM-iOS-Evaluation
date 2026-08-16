//
//  TaskSortOrder.swift
//  TaskManager
//

import Foundation

/// How the fetched tasks should be ordered.
nonisolated enum TaskSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dueDate
    case urgency
    case created
    case title

    var id: Self { self }

    var name: String {
        switch self {
        case .dueDate: "Due Date"
        case .urgency: "Urgency"
        case .created: "Date Added"
        case .title: "Title"
        }
    }
}
