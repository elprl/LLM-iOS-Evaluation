//
//  AddTaskView.swift
//  TaskManager
//

import SwiftUI

/// Collects a ``TaskDraft`` and hands it back to the caller.
///
/// The view never touches persistence — it builds a `Sendable` value and lets the view model
/// forward it to the data actor.
struct AddTaskView: View {
    let onAdd: (TaskDraft) -> Void

    @State private var draft = TaskDraft()
    @State private var hasDueDate = false
    @State private var dueDate: Date = .now

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Notes", text: $draft.details, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Picker("Urgency", selection: $draft.urgency) {
                        ForEach(TaskUrgency.allCases) { urgency in
                            Label(urgency.name, systemImage: urgency.symbolName)
                                .tag(urgency)
                        }
                    }

                    Toggle("Has due date", isOn: $hasDueDate.animation())

                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(draft.isValid == false)
                }
            }
        }
    }

    private func add() {
        var newTask = draft
        newTask.dueDate = hasDueDate ? dueDate : nil
        onAdd(newTask)
        dismiss()
    }
}

#Preview {
    AddTaskView { _ in }
}
