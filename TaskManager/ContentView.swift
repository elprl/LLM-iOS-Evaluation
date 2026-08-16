import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var viewModel: TaskListViewModel
    @State private var newTaskTitle = ""

    init(modelContainer: ModelContainer) {
        _viewModel = State(
            initialValue: TaskListViewModel(modelContainer: modelContainer)
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                Section("New Task") {
                    HStack {
                        TextField("What needs doing?", text: $newTaskTitle)
                            .submitLabel(.done)
                            .onSubmit(addTask)

                        Button("Add Task", systemImage: "plus", action: addTask)
                            .labelStyle(.iconOnly)
                            .disabled(cannotAddTask)
                    }
                }

                Section("Tasks") {
                    if viewModel.isLoading, viewModel.tasks.isEmpty {
                        ProgressView("Loading tasks")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.tasks.isEmpty {
                        ContentUnavailableView(
                            "No Tasks",
                            systemImage: "checklist",
                            description: Text("Add a task to get started.")
                        )
                    } else {
                        ForEach(viewModel.tasks) { task in
                            TaskRowView(task: task) {
                                toggleTask(id: task.id)
                            }
                        }
                        .onDelete(perform: deleteTasks)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                if !viewModel.tasks.isEmpty {
                    EditButton()
                }
            }
            .disabled(viewModel.isPerformingMutation)
            .overlay {
                if viewModel.isPerformingMutation {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .task {
                await viewModel.loadTasks()
            }
            .alert("Unable to Update Tasks", isPresented: $viewModel.isShowingError) {
                Button("OK", action: viewModel.dismissError)
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var cannotAddTask: Bool {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.isPerformingMutation
    }

    private func addTask() {
        let title = newTaskTitle

        Task {
            if await viewModel.addTask(title: title) {
                newTaskTitle = ""
            }
        }
    }

    private func toggleTask(id: UUID) {
        Task {
            await viewModel.toggleTask(id: id)
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        let ids = offsets.map { viewModel.tasks[$0].id }

        Task {
            await viewModel.deleteTasks(ids: ids)
        }
    }

    fileprivate static let previewModelContainer: ModelContainer = {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: TaskEntity.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create preview model container: \(error)")
        }
    }()
}

#Preview {
    ContentView(modelContainer: ContentView.previewModelContainer)
        .modelContainer(ContentView.previewModelContainer)
}
