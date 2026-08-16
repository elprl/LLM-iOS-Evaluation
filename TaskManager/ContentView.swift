import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var viewModel: TaskListViewModel
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""

    init(modelContainer: ModelContainer) {
        _viewModel = State(initialValue: TaskListViewModel(modelContainer: modelContainer))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                ForEach(viewModel.tasks) { task in
                    TaskRow(task: task, onToggle: { toggle(task) })
                }
                .onDelete(perform: deleteTasks)
            }
            .overlay {
                if viewModel.tasks.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Add a task to get started.")
                    )
                } else if viewModel.isLoading, viewModel.tasks.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Task", systemImage: "plus", action: presentAddTask)
                }
            }
            .alert("New Task", isPresented: $isAddingTask) {
                TextField("Title", text: $newTaskTitle)
                Button("Add", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel, action: cancelAddTask)
            }
            .alert("Error", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadTasks()
            }
        }
    }

    private func presentAddTask() {
        isAddingTask = true
    }

    private func addTask() {
        let title = newTaskTitle
        newTaskTitle = ""
        Task { await viewModel.addTask(title: title) }
    }

    private func cancelAddTask() {
        newTaskTitle = ""
    }

    private func toggle(_ task: TaskDTO) {
        Task { await viewModel.toggleTask(task) }
    }

    private func deleteTasks(at offsets: IndexSet) {
        let ids = offsets.map { viewModel.tasks[$0].id }
        Task { await viewModel.deleteTasks(ids: ids) }
    }
}

#Preview {
    ContentView(modelContainer: .preview)
}

private extension ModelContainer {
    static var preview: ModelContainer {
        do {
            let container = try ModelContainer(
                for: TaskItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            context.insert(TaskItem(title: "Buy groceries"))
            context.insert(TaskItem(title: "Write report", isCompleted: true))
            try context.save()
            return container
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }
}
