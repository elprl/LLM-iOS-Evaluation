import SwiftUI

struct TaskRow: View {
    let task: TaskDTO
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .foregroundStyle(.primary)
                        .strikethrough(task.isCompleted)
                    Text(task.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityValue(task.isCompleted ? "Completed" : "Not completed")
        .accessibilityHint("Toggles completion")
    }
}
