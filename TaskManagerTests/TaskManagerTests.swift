import SwiftData
import Testing
@testable import TaskManager

@MainActor
struct TaskManagerTests {
    @Test
    func repositoryPerformsCRUDUsingSendableSnapshots() async throws {
        let container = try makeContainer()
        let repository = await TaskRepositoryFactory.make(modelContainer: container)

        var tasks = try await repository.fetchTasks()
        #expect(tasks.isEmpty)

        tasks = try await repository.addTask(title: "Write concurrency sample")
        let task = try #require(tasks.first)
        #expect(task.title == "Write concurrency sample")
        #expect(!task.isCompleted)

        tasks = try await repository.toggleTask(id: task.id)
        #expect(tasks.first?.isCompleted == true)

        tasks = try await repository.deleteTasks(ids: [task.id])
        #expect(tasks.isEmpty)
    }

    @Test
    func viewModelOwnsMainActorState() async throws {
        let viewModel = TaskListViewModel(modelContainer: try makeContainer())

        await viewModel.loadTasks()
        #expect(viewModel.tasks.isEmpty)

        let didAddTask = await viewModel.addTask(title: "  Ship the app  ")
        #expect(didAddTask)
        #expect(viewModel.tasks.first?.title == "Ship the app")

        let task = try #require(viewModel.tasks.first)
        await viewModel.toggleTask(id: task.id)
        #expect(viewModel.tasks.first?.isCompleted == true)

        await viewModel.deleteTasks(ids: [task.id])
        #expect(viewModel.tasks.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TaskEntity.self,
            configurations: configuration
        )
    }
}
