//
//  TaskRowView.swift
//  TaskManager
//

import SwiftUI
import SwiftData

/// A single row in the task list.
///
/// It reads from a ``TaskSnapshot`` value rather than a live `TaskItem`, so rendering can
/// never touch a model owned by another actor's context. The property is called `snapshot`
/// rather than `task` so it doesn't shadow SwiftUI's `task` modifier inside `body`.
struct TaskRowView: View {
    let snapshot: TaskSnapshot
    let onToggleCompletion: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                onToggleCompletion(snapshot.isCompleted == false)
            } label: {
                Image(systemName: snapshot.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(snapshot.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapshot.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .strikethrough(snapshot.isCompleted)
                    .foregroundStyle(snapshot.isCompleted ? .secondary : .primary)

                if snapshot.details.isEmpty == false {
                    Text(snapshot.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let dueDate = snapshot.dueDate {
                    Label {
                        Text(dueDate, format: .dateTime.day().month().year())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(snapshot.isOverdue ? .red : .secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: snapshot.urgency.symbolName)
                .foregroundStyle(urgencyColor)
                .accessibilityLabel("\(snapshot.urgency.name) urgency")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var urgencyColor: Color {
        switch snapshot.urgency {
        case .low: .secondary
        case .normal: .blue
        case .high: .orange
        }
    }
}

#Preview {
    TaskRowPreview()
}

/// Wrapper so the preview can build a real `TaskItem` (and therefore a real snapshot)
/// without putting statements inside a `ViewBuilder`.
private struct TaskRowPreview: View {
    private let snapshot: TaskSnapshot

    init() {
        let container = ModelContainerFactory.makePreviewContainer()
        let context = ModelContext(container)
        let item = TaskItem(
            title: "Ship the concurrency refactor",
            details: "Snapshots cross the boundary, models stay put.",
            dueDate: .now,
            urgency: .high
        )
        context.insert(item)
        snapshot = TaskSnapshot(item)
    }

    var body: some View {
        List {
            TaskRowView(snapshot: snapshot) { _ in }
        }
    }
}
