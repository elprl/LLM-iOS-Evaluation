import SwiftUI

struct ContentView: View {
    var viewModel: TaskListViewModel
    @State private var newTaskTitle = ""

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Tasks")
                .safeAreaInset(edge: .bottom) { addTaskBar }
        }
        .task { await viewModel.loadTasks() }
        .refreshable { await viewModel.loadTasks() }
        .alert("Error", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var list: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            ProgressView("Loading tasks…")
        } else if viewModel.tasks.isEmpty {
            ContentUnavailableView(
                "No Tasks",
                systemImage: "checklist",
                description: Text("Add your first task below.")
            )
        } else {
            List {
                ForEach(viewModel.tasks) { task in
                    row(for: task)
                }
                .onDelete { offsets in
                    Task { await viewModel.deleteTasks(at: offsets) }
                }
            }
        }
    }

    private func row(for task: TaskDTO) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.toggleTask(id: task.id) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                Text(task.createdAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addTaskBar: some View {
        HStack(spacing: 8) {
            TextField("New task", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitNewTask)
            Button(action: submitNewTask) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Helpers

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func submitNewTask() {
        let title = newTaskTitle
        newTaskTitle = ""
        Task { await viewModel.addTask(title) }
    }
}

#Preview {
    @Previewable var viewModel = TaskListViewModel.makePreview()
    ContentView(viewModel: viewModel)
}
