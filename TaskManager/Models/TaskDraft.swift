//
//  TaskDraft.swift
//  TaskManager
//

import Foundation

/// The data needed to create a new task, as a `Sendable` value.
///
/// Sending a draft rather than a half-built `TaskItem` means the model object is only ever
/// constructed inside ``TaskDataActor``, on the context that will own it.
nonisolated struct TaskDraft: Hashable, Sendable {
    var title: String = ""
    var details: String = ""
    var dueDate: Date?
    var urgency: TaskUrgency = .normal

    var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
