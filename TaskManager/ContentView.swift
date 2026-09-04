//
//  ContentView.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel: TaskListViewModel
    @State private var isPresentingAddTaskSheet: Bool = false

    init(viewModel: TaskListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Segmented Control
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(TaskFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if let errorMessage = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                // Task List / Empty State
                if viewModel.displayedTasks.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checklist")
                    } description: {
                        Text(viewModel.searchText.isEmpty ? "Tap '+' to create your first task." : "No tasks match your search.")
                    } actions: {
                        if viewModel.searchText.isEmpty {
                            Button("Add Task") {
                                isPresentingAddTaskSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.displayedTasks) { task in
                            TaskRowView(task: task) {
                                Task {
                                    await viewModel.toggleCompletion(for: task)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.delete(task: task)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                await viewModel.delete(at: indexSet)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .overlay {
                        if viewModel.isLoading && viewModel.tasks.isEmpty {
                            ProgressView("Loading tasks...")
                        }
                    }
                }
            }
            .navigationTitle("Task Manager")
            .searchable(text: $viewModel.searchText, prompt: "Search tasks...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortBy) {
                            ForEach(TaskSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddTaskSheet = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddTaskSheet) {
                AddTaskSheetView { title, note, priority, dueDate in
                    Task {
                        await viewModel.addTask(
                            title: title,
                            note: note,
                            priority: priority,
                            dueDate: dueDate
                        )
                    }
                }
            }
            .task {
                await viewModel.seedInitialDataIfNeeded()
            }
            .refreshable {
                await viewModel.loadTasks()
            }
        }
    }
}

// MARK: - Task Row View

private struct TaskRowView: View {
    let task: TaskItemDTO
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.isCompleted ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)

                    Spacer()

                    PriorityBadge(priority: task.priority)
                }

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if let dueDate = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(dueDate, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                    }
                    .foregroundColor(isPastDue(dueDate, isCompleted: task.isCompleted) ? .red : .secondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func isPastDue(_ date: Date, isCompleted: Bool) -> Bool {
        !isCompleted && date < Date()
    }
}

// MARK: - Priority Badge View

private struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.title)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundColor(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .red
        }
    }
}

// MARK: - Add Task Sheet View

private struct AddTaskSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var includeDueDate: Bool = false
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    let onSave: (String, String, TaskPriority, Date?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                    TextField("Notes (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $includeDueDate)
                    if includeDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date])
                    }
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
                        onSave(title, note, priority, includeDueDate ? dueDate : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview Provider

#Preview {
    ContentView(viewModel: .preview)
}
