//
//  AddTaskView.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import SwiftUI

public struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var priority: TaskPriority = .medium
    @FocusState private var isTitleFocused: Bool

    public let onSave: @Sendable (String, TaskPriority) async -> Void

    public init(onSave: @escaping @Sendable (String, TaskPriority) async -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("What needs to be done?", text: $title, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isTitleFocused)

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let savedTitle = title
                        let savedPriority = priority
                        dismiss()
                        Task {
                            await onSave(savedTitle, savedPriority)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }
}
