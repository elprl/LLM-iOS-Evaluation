import SwiftUI

struct TaskRowView: View {
    let task: TaskSnapshot
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(
                task.isCompleted ? "Mark Incomplete" : "Mark Complete",
                systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle",
                action: toggle
            )
            .labelStyle(.iconOnly)
            .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                Text(task.createdAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
