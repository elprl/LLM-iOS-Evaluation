//
//  TaskListView.swift
//  TaskManager
//

import SwiftUI
import SwiftData

/// Lists tasks fetched on a background `ModelActor`.
struct TaskListView: View {
    @Bindable var viewModel: TaskListViewModel

    @State private var isAddingTask = false

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("Tasks")
                // Inline, because the filter picker occupies the space a large title
                // would otherwise animate into.
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $viewModel.searchText, prompt: "Search tasks")
                .toolbar { toolbarContent }
                .toolbarTitleMenu { sortMenu }
                .safeAreaInset(edge: .top) { filterPicker }
                // Every change to search text, filter, or sort order cancels the in-flight
                // fetch and starts a new one on the data actor.
                .task(id: viewModel.query) {
                    await viewModel.load(viewModel.query)
                }
                .task {
                    await viewModel.start()
                }
                .sheet(isPresented: $isAddingTask) {
                    AddTaskView { draft in
                        Task { await viewModel.addTask(draft) }
                    }
                }
                .alert("Something went wrong", isPresented: $viewModel.isShowingError) {
                    Button("OK") { viewModel.isShowingError = false }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.tasks) { snapshot in
                    TaskRowView(snapshot: snapshot) { isCompleted in
                        Task { await viewModel.setCompletion(isCompleted, for: snapshot) }
                    }
                }
                .onDelete { offsets in
                    Task { await viewModel.delete(at: offsets) }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: viewModel.tasks)
            .overlay {
                if viewModel.state == .loading {
                    ProgressView()
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.state {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load tasks", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.load(viewModel.query, debounce: false) }
                }
            }
        default:
            if viewModel.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "checkmark.circle")
                } description: {
                    Text("Tasks you add will appear here.")
                } actions: {
                    Button("Add Task") { isAddingTask = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $viewModel.filter) {
            ForEach(TaskFilter.allCases) { filter in
                Text(filter.name).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var sortMenu: some View {
        Picker("Sort By", selection: $viewModel.sortOrder) {
            ForEach(TaskSortOrder.allCases) { order in
                Text(order.name).tag(order)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add Task", systemImage: "plus") {
                isAddingTask = true
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            EditButton()
        }
    }
}

#Preview {
    TaskListPreview()
}

/// Wrapper for the preview.
///
/// The `TaskDataActor` is built here rather than directly inside `#Preview` because the
/// initializer synthesised by `@ModelActor` isn't visible from inside another macro's
/// expansion.
private struct TaskListPreview: View {
    @State private var viewModel = TaskListViewModel(
        store: TaskDataActor(modelContainer: ModelContainerFactory.makePreviewContainer())
    )

    var body: some View {
        TaskListView(viewModel: viewModel)
    }
}
