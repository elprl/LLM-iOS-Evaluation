//
//  TaskUrgency.swift
//  TaskManager
//

import Foundation

/// How urgent a task is.
///
/// Named `TaskUrgency` rather than `TaskPriority` to avoid shadowing the standard library's
/// `TaskPriority` from Swift concurrency.
///
/// `nonisolated` keeps the type off the main actor under this target's default-MainActor
/// isolation, which is what allows it to be used freely from ``TaskDataActor``.
nonisolated enum TaskUrgency: Int, CaseIterable, Codable, Comparable, Identifiable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    var symbolName: String {
        switch self {
        case .low: "arrow.down.circle"
        case .normal: "minus.circle"
        case .high: "exclamationmark.circle"
        }
    }

    static func < (lhs: TaskUrgency, rhs: TaskUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
