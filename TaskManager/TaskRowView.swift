//
//  TaskRowView.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import SwiftUI

public struct TaskRowView: View {
    public let task: TaskDTO
    public let onToggle: () -> Void

    public init(task: TaskDTO, onToggle: @escaping () -> Void) {
        self.task = task
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark task incomplete" : "Mark task complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    priorityBadge(for: task.priority)

                    Text(task.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func priorityBadge(for priority: TaskPriority) -> some View {
        let (color, bg) = badgeColors(for: priority)
        Text(priority.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg, in: Capsule())
    }

    private func badgeColors(for priority: TaskPriority) -> (Color, Color) {
        switch priority {
        case .low:
            return (.gray, Color(.systemGray6))
        case .medium:
            return (.blue, Color.blue.opacity(0.12))
        case .high:
            return (.orange, Color.orange.opacity(0.15))
        case .urgent:
            return (.red, Color.red.opacity(0.15))
        }
    }
}
