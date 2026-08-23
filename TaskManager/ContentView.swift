//
//  ContentView.swift
//  TaskManager
//
//  Created by Paul Leo on 16/08/2026.
//

import SwiftUI
import SwiftData

public struct ContentView: View {
    @State private var viewModel: TaskListViewModel

    public init(modelContainer: ModelContainer) {
        _viewModel = State(wrappedValue: TaskListViewModel(modelContainer: modelContainer))
    }

    public var body: some View {
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

                // Task List / Empty State
                List {
                    if viewModel.filteredTasks.isEmpty {
                        ContentUnavailableView {
                            Label(
                                viewModel.searchText.isEmpty ? "No Tasks" : "No Results",
                                systemImage: viewModel.searchText.isEmpty ? "checklist" : "magnifyingglass"
                            )
                        } description: {
                            Text(emptyStateDescription)
                        } actions: {
                            if viewModel.tasks.isEmpty {
                                Button("Add Sample Tasks") {
                                    Task {
                                        await viewModel.seedSampleDataIfNeeded()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(viewModel.filteredTasks) { task in
                            TaskRowView(task: task) {
                                Task {
                                    await viewModel.toggleTaskCompletion(task)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task {
                                        await viewModel.toggleTaskCompletion(task)
                                    }
                                } label: {
                                    Label(
                                        task.isCompleted ? "Mark Incomplete" : "Mark Complete",
                                        systemImage: task.isCompleted ? "circle" : "checkmark.circle"
                                    )
                                }
                                .tint(task.isCompleted ? .orange : .green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteTask(task)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            Task {
                                await viewModel.deleteTasks(at: offsets)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadTasks()
                }
                .searchable(text: $viewModel.searchText, prompt: "Search tasks...")
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortOrder) {
                            ForEach(TaskSortOrder.allCases) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }

                        Divider()

                        Menu("Filter by Priority") {
                            Button("All Priorities") {
                                viewModel.priorityFilter = nil
                            }
                            ForEach(TaskPriority.allCases, id: \.self) { priority in
                                Button(priority.rawValue) {
                                    viewModel.priorityFilter = priority
                                }
                            }
                        }

                        Divider()

                        Button(action: {
                            Task {
                                await viewModel.seedSampleDataIfNeeded()
                            }
                        }) {
                            Label("Add Sample Tasks", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add New Task")
                }
            }
            .sheet(isPresented: $viewModel.isShowingAddSheet) {
                AddTaskView { title, priority in
                    await viewModel.addTask(title: title, priority: priority)
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.clearError() } }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        viewModel.clearError()
                    }
                },
                message: {
                    Text(viewModel.errorMessage ?? "")
                }
            )
            .task {
                await viewModel.loadTasks()
                await viewModel.seedSampleDataIfNeeded()
            }
        }
    }

    private var emptyStateDescription: String {
        if !viewModel.searchText.isEmpty {
            return "No tasks matching '\(viewModel.searchText)'."
        }
        switch viewModel.filter {
        case .all:
            return "You have no tasks. Tap + or add sample tasks to get started."
        case .active:
            return "No active tasks remaining. Great job!"
        case .completed:
            return "No completed tasks yet."
        }
    }
}

#Preview {
    let schema = Schema([TaskItem.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return ContentView(modelContainer: container)
}
