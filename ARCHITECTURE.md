# Architecture & Concurrency Guide: SwiftData in Swift 6

This document details the architectural design, rationale, and implementation of the **TaskManager** iOS application. The project demonstrates a production-ready, strict-concurrency-compliant Swift 6 architecture combining **SwiftUI**, **SwiftData**, and **MVVM** using modern Swift macros (`@Model`, `@ModelActor`, `@Observable`).

---

## Table of Contents
1. [Architectural Overview](#1-architectural-overview)
2. [The Swift 6 Concurrency Challenge with SwiftData](#2-the-swift-6-concurrency-challenge-with-swiftdata)
3. [Solving "Sendability Hell": The Sendable DTO Pattern](#3-solving-sendability-hell-the-sendable-dto-pattern)
4. [Background Persistence Layer: `@ModelActor`](#4-background-persistence-layer-modelactor)
5. [Presentation Layer: `@Observable` MVVM on `@MainActor`](#5-presentation-layer-observable-mvvm-on-mainactor)
6. [Declarative UI Layer: SwiftUI & Async Lifecycle](#6-declarative-ui-layer-swiftui--async-lifecycle)
7. [App Lifecycle & Dependency Injection](#7-app-lifecycle--dependency-injection)
8. [Swift Testing Verification Suite](#8-swift-testing-verification-suite)
9. [Key Architectural Decisions & Rationale](#9-key-architectural-decisions--rationale)

---

## 1. Architectural Overview

The application follows a unidirectional, decoupled MVVM architecture structured across distinct actor isolation domains:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        @MainActor Domain                               │
│                                                                        │
│   ┌───────────────────────────────┐     ┌───────────────────────────┐  │
│   │          ContentView          │     │     TaskListViewModel     │  │
│   │        (SwiftUI View)         │◄───►│       (@Observable)       │  │
│   │                               │     │                           │  │
│   │  • List of tasks              │     │  • tasks: [TaskItemDTO]   │  │
│   │  • Add task sheet             │     │  • Filter & Sort state    │  │
│   │  • Search & filtering         │     │  • Async intent handlers  │  │
│   │  • .task / .refreshable       │     │                           │  │
│   └───────────────────────────────┘     └─────────────┬─────────────┘  │
└───────────────────────────────────────────────────────┼────────────────┘
                                            async/await │ Sendable DTOs
                                                        ▼ & PersistentIdentifiers
┌────────────────────────────────────────────────────────────────────────┐
│                   TaskModelActor (@ModelActor)                         │
│                    (Background Actor Domain)                           │
│                                                                        │
│   • Background Queries: FetchDescriptor<TaskItem> (Predicate & Sort)   │
│   • Transforms TaskItem (non-Sendable @Model) ➔ TaskItemDTO (Sendable) │
│   • Safe background mutations (add, toggle completion, delete, seed)   │
│   • Isolated ModelContext & ModelExecutor on cooperative thread pool   │
│   • Interacts directly with persistent storage (SQLite/SwiftData)      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Swift 6 Concurrency Challenge with SwiftData

In Swift 6 mode (`SWIFT_STRICT_CONCURRENCY = complete`), data isolation boundaries are strictly enforced at compile time. Data crossing between actors (such as between a background persistence worker and the `@MainActor` UI) must conform to `Sendable`.

### Why `@Model` Classes Cause "Sendability Hell"
SwiftData models created with `@Model` are managed reference types:
1. **Context Binding**: Every `@Model` instance is bound to a specific `ModelContext`.
2. **Lazy Faulting & Mutations**: Reading relationships or mutating properties touches the underlying managed context.
3. **Non-Sendable by Design**: `PersistentModel` intentionally does not conform to `Sendable`. If an instance is accessed across different threads or actors, data races, corrupted SQLite state, or runtime crashes occur.
4. **Compiler Rejection**: Passing `[TaskItem]` from a background worker to `@MainActor` produces a fatal compile error:
   ```text
   error: sending 'task' risks causing data races
   note: task of non-Sendable type 'TaskItem' transferred across actor boundary
   ```
5. **Anti-pattern to Avoid**: Marking a `@Model` class as `@unchecked Sendable` bypasses compiler diagnostics but leads to intermittent crashes in production when the context faults on a background thread while the UI reads on the main thread.

---

## 3. Solving "Sendability Hell": The Sendable DTO Pattern

To achieve complete thread safety and avoid compiler warnings or runtime bugs, the persistence entities are isolated entirely within the background layer. Only immutable value types conformant to `Sendable` cross the actor boundary.

### `PersistentIdentifier` as the Bridge
SwiftData provides `PersistentIdentifier`, which is a lightweight struct that identifies an entity. Crucially:
- `PersistentIdentifier` conforms to `Sendable`, `Hashable`, and `Equatable`.
- It can safely travel between the background `@ModelActor` and the `@MainActor` ViewModel.

### Implementation: `TaskItemDTO.swift`

```swift
import Foundation
import SwiftData

/// Represents the priority level of a task.
/// Conforms to `Sendable` and `Identifiable` so it can be safely transferred across actor boundaries
/// and used directly in SwiftUI ForEach pickers.
public enum TaskPriority: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Filter options for listing tasks.
public enum TaskFilter: String, Sendable, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"

    public var id: String { rawValue }
}

/// Sort options for listing tasks.
public enum TaskSortOption: String, Sendable, CaseIterable, Identifiable {
    case createdAt = "Created"
    case priority = "Priority"
    case title = "Title"

    public var id: String { rawValue }
}

/// An immutable, Sendable Data Transfer Object (DTO) representing a `TaskItem`.
///
/// In Swift 6 strict concurrency, SwiftData `@Model` classes cannot be passed across
/// actor boundaries because they are reference types tied to a specific `ModelContext`.
/// `TaskItemDTO` bridges this boundary by copying model values into a value type,
/// using SwiftData's Sendable `PersistentIdentifier` as its stable identity.
public struct TaskItemDTO: Identifiable, Sendable, Hashable {
    public let id: PersistentIdentifier
    public let title: String
    public let note: String
    public let isCompleted: Bool
    public let priority: TaskPriority
    public let dueDate: Date?
    public let createdAt: Date

    public nonisolated init(
        id: PersistentIdentifier,
        title: String,
        note: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
        self.createdAt = createdAt
    }
}
```

### Implementation: `TaskItem.swift`

```swift
import Foundation
import SwiftData

/// SwiftData PersistentModel representing a stored task.
///
/// NOTE: In Swift 6, `@Model` classes are non-Sendable reference types bound to a `ModelContext`.
/// They should NOT be passed across actor boundaries. Instead, perform operations within
/// the `@ModelActor` and transform into or out of `TaskItemDTO`.
@Model
public final class TaskItem {
    public var title: String
    public var note: String
    public var isCompleted: Bool
    public var priorityRaw: Int
    public var dueDate: Date?
    public var createdAt: Date

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    public init(
        title: String,
        note: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.note = note
        self.isCompleted = isCompleted
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.createdAt = createdAt
    }

    /// Converts this SwiftData entity into an immutable, Sendable DTO for cross-actor communication.
    public func toDTO() -> TaskItemDTO {
        TaskItemDTO(
            id: persistentModelID,
            title: title,
            note: note,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            createdAt: createdAt
        )
    }
}
```

---

## 4. Background Persistence Layer: `@ModelActor`

In SwiftData, background persistence should not rely on manually created contexts inside arbitrary detached tasks. Instead, Apple provides the `@ModelActor` macro.

### What `@ModelActor` Generates Under the Hood
When annotating an actor with `@ModelActor`:
1. Synthesizes `nonisolated let modelExecutor: any ModelExecutor`.
2. Synthesizes `nonisolated let modelContainer: ModelContainer`.
3. Synthesizes `init(modelContainer: ModelContainer)` creating a dedicated `ModelContext` associated with a serial `ModelExecutor`.
4. Guarantees that all access to `self.modelContext` happens on the actor's private executor, running on the cooperative thread pool off the main thread.

### Implementation: `TaskModelActor.swift`

```swift
import Foundation
import SwiftData

/// A background actor responsible for SwiftData persistence queries and mutations.
///
/// By using the `@ModelActor` macro, this actor provides safe, isolated background execution
/// with its own `ModelExecutor` and `ModelContext`.
///
/// To prevent Swift 6 strict concurrency data races, all methods return Sendable `TaskItemDTO`
/// instances instead of passing the non-Sendable `@Model TaskItem` reference type.
@ModelActor
actor TaskModelActor {

    /// Fetches tasks matching the specified filter and sort order in the background.
    /// - Parameters:
    ///   - filter: Filter criterion (`.all`, `.pending`, `.completed`).
    ///   - sortBy: Sort criterion (`.createdAt`, `.priority`, `.title`).
    /// - Returns: An array of Sendable `TaskItemDTO` value types safe to pass to `@MainActor`.
    func fetchTasks(
        filter: TaskFilter = .all,
        sortBy: TaskSortOption = .createdAt
    ) throws -> [TaskItemDTO] {
        var descriptor: FetchDescriptor<TaskItem>

        switch filter {
        case .all:
            descriptor = FetchDescriptor<TaskItem>()
        case .pending:
            descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })
        case .completed:
            descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCompleted })
        }

        switch sortBy {
        case .createdAt:
            descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        case .priority:
            descriptor.sortBy = [
                SortDescriptor(\.priorityRaw, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        case .title:
            descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        }

        let items = try modelContext.fetch(descriptor)
        return items.map { $0.toDTO() }
    }

    /// Inserts a new task in the background and saves the context.
    func addTask(
        title: String,
        note: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) throws -> TaskItemDTO {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(
            title: trimmedTitle,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: false,
            priority: priority,
            dueDate: dueDate,
            createdAt: Date()
        )
        modelContext.insert(task)
        try modelContext.save()
        return task.toDTO()
    }

    /// Toggles the completion status of a task by its Sendable `PersistentIdentifier`.
    func toggleTaskCompletion(id: PersistentIdentifier) throws -> TaskItemDTO? {
        guard let task = modelContext.model(for: id) as? TaskItem else {
            return nil
        }
        task.isCompleted.toggle()
        try modelContext.save()
        return task.toDTO()
    }

    /// Deletes a single task identified by its `PersistentIdentifier`.
    func deleteTask(id: PersistentIdentifier) throws {
        if let task = modelContext.model(for: id) as? TaskItem {
            modelContext.delete(task)
            try modelContext.save()
        }
    }

    /// Deletes multiple tasks identified by their `PersistentIdentifier`s.
    func deleteTasks(ids: [PersistentIdentifier]) throws {
        for id in ids {
            if let task = modelContext.model(for: id) as? TaskItem {
                modelContext.delete(task)
            }
        }
        try modelContext.save()
    }

    /// Seeds default sample tasks if the database is currently empty.
    func seedDefaultTasksIfNeeded() throws {
        var descriptor = FetchDescriptor<TaskItem>()
        descriptor.fetchLimit = 1
        let count = try modelContext.fetchCount(descriptor)
        guard count == 0 else { return }

        let samples: [(String, String, TaskPriority, Date?)] = [
            (
                "Adopt Swift 6 Strict Concurrency",
                "Audit cross-actor boundaries and ensure Sendable conformance.",
                .high,
                Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ),
            (
                "Implement @ModelActor background worker",
                "Execute SwiftData fetch descriptors off the main thread.",
                .high,
                Calendar.current.date(byAdding: .day, value: 2, to: Date())
            ),
            (
                "Build modern @Observable ViewModel",
                "Bind UI state to MainActor with clean async/await interactions.",
                .medium,
                Calendar.current.date(byAdding: .day, value: 3, to: Date())
            ),
            (
                "Write Swift Testing verification suite",
                "Test background CRUD and Sendable DTO serialization.",
                .low,
                nil
            )
        ]

        for sample in samples {
            let task = TaskItem(
                title: sample.0,
                note: sample.1,
                isCompleted: false,
                priority: sample.2,
                dueDate: sample.3,
                createdAt: Date()
            )
            modelContext.insert(task)
        }
        try modelContext.save()
    }
}
```

---

## 5. Presentation Layer: `@Observable` MVVM on `@MainActor`

### Modern Macro Observation
Instead of legacy `ObservableObject` and `@Published` property wrappers, the ViewModel adopts the `@Observable` macro introduced with the Swift Observation framework:
- **Zero Boilerplate**: No `@Published` annotations required.
- **Granular Observation**: SwiftUI views only re-render when properties they directly read change.
- **`@MainActor` Bound**: Guarantees all published state mutations happen exclusively on the main thread.

### Implementation: `TaskListViewModel.swift`

```swift
import Foundation
import SwiftData
import Observation

/// The main UI ViewModel for the task list.
///
/// Features:
/// - Uses the modern `@Observable` macro for seamless observation in SwiftUI.
/// - Bound to `@MainActor` to safely drive SwiftUI view updates.
/// - Communicates with the background `TaskModelActor` exclusively via `async/await` and `Sendable` DTOs,
///   guaranteeing complete Swift 6 thread safety without any data races or Sendable warnings.
@Observable
@MainActor
final class TaskListViewModel {

    // MARK: - Published State

    var tasks: [TaskItemDTO] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var filter: TaskFilter = .all {
        didSet {
            Task { await loadTasks() }
        }
    }
    var sortBy: TaskSortOption = .createdAt {
        didSet {
            Task { await loadTasks() }
        }
    }
    var searchText: String = ""

    // MARK: - Filtered Presentation

    var displayedTasks: [TaskItemDTO] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tasks
        }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Dependencies

    private let modelActor: TaskModelActor

    // MARK: - Initialization

    init(modelActor: TaskModelActor) {
        self.modelActor = modelActor
    }

    // MARK: - Async Intent Methods

    /// Loads tasks asynchronously from the background actor.
    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Background query performed off the main thread by TaskModelActor
            let fetchedTasks = try await modelActor.fetchTasks(filter: filter, sortBy: sortBy)
            self.tasks = fetchedTasks
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    /// Pre-populates sample tasks if the database is currently empty.
    func seedInitialDataIfNeeded() async {
        do {
            try await modelActor.seedDefaultTasksIfNeeded()
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to seed sample data: \(error.localizedDescription)"
        }
    }

    /// Adds a new task in the background.
    func addTask(
        title: String,
        note: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            _ = try await modelActor.addTask(
                title: title,
                note: note,
                priority: priority,
                dueDate: dueDate
            )
            await loadTasks()
        } catch {
            self.errorMessage = "Failed to add task: \(error.localizedDescription)"
        }
    }

    /// Toggles task completion status in the background.
    func toggleCompletion(for task: TaskItemDTO) async {
        // Optimistic local update for instantaneous UI feedback
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = TaskItemDTO(
                id: task.id,
                title: task.title,
                note: task.note,
                isCompleted: !task.isCompleted,
                priority: task.priority,
                dueDate: task.dueDate,
                createdAt: task.createdAt
            )
        }

        do {
            _ = try await modelActor.toggleTaskCompletion(id: task.id)
        } catch {
            // Revert on failure
            self.errorMessage = "Failed to update task: \(error.localizedDescription)"
            await loadTasks()
        }
    }

    /// Deletes tasks at specific index offsets within the currently displayed list.
    func delete(at offsets: IndexSet) async {
        let targets = offsets.map { displayedTasks[$0] }
        let idsToDelete = targets.map(\.id)

        // Optimistic UI removal
        tasks.removeAll(where: { idsToDelete.contains($0.id) })

        do {
            try await modelActor.deleteTasks(ids: idsToDelete)
        } catch {
            self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
            await loadTasks()
        }
    }

    /// Deletes a specific task.
    func delete(task: TaskItemDTO) async {
        tasks.removeAll(where: { $0.id == task.id })

        do {
            try await modelActor.deleteTask(id: task.id)
        } catch {
            self.errorMessage = "Failed to delete task: \(error.localizedDescription)"
            await loadTasks()
        }
    }
}

// MARK: - Preview Factory

extension TaskListViewModel {
    static var preview: TaskListViewModel {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let actor = TaskModelActor(modelContainer: container)
        return TaskListViewModel(modelActor: actor)
    }
}
```

---

## 6. Declarative UI Layer: SwiftUI & Async Lifecycle

### Eliminating Direct Database Coupling in Views
Standard SwiftUI templates place `@Query` directly in Views. While convenient for simple apps, this couples UI views directly to the persistence store and forces database faults onto `@MainActor`.

In this architecture:
- `ContentView` contains **no** `@Query` or `@Environment(\.modelContext)`.
- It observes `TaskListViewModel`.
- Async tasks run via `.task { await viewModel.seedInitialDataIfNeeded() }`.
- Pull-to-refresh is provided via `.refreshable { await viewModel.loadTasks() }`.

### Implementation: `ContentView.swift`

```swift
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
```

---

## 7. App Lifecycle & Dependency Injection

`TaskManagerApp` sets up the persistent storage container, constructs the background actor, and injects it into the ViewModel.

### Implementation: `TaskManagerApp.swift`

```swift
import SwiftUI
import SwiftData

@main
struct TaskManagerApp: App {
    let sharedModelContainer: ModelContainer
    @State private var viewModel: TaskListViewModel

    init() {
        let schema = Schema([
            TaskItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
            let actor = TaskModelActor(modelContainer: container)
            _viewModel = State(initialValue: TaskListViewModel(modelActor: actor))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

---

## 8. Swift Testing Verification Suite

The project includes unit tests leveraging Apple's modern **Swift Testing** framework (`import Testing`). Tests execute asynchronously against in-memory `ModelContainer` instances, validating data persistence, filtering, ViewModel synchronization, and actor serialization under concurrent execution.

### Implementation: `TaskManagerTests.swift`

```swift
import Testing
import Foundation
import SwiftData
@testable import TaskManager

@Suite("SwiftData Swift 6 Strict Concurrency Tests")
struct TaskManagerTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("TaskModelActor performs background insert and fetch safely")
    func testBackgroundInsertAndFetch() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        // Insert task via background actor
        let createdDTO = try await actor.addTask(
            title: "Test Task 1",
            note: "First note",
            priority: .high,
            dueDate: nil
        )

        #expect(createdDTO.title == "Test Task 1")
        #expect(createdDTO.note == "First note")
        #expect(createdDTO.priority == .high)
        #expect(createdDTO.isCompleted == false)

        // Fetch back from actor
        let allTasks = try await actor.fetchTasks(filter: .all, sortBy: .createdAt)
        #expect(allTasks.count == 1)
        #expect(allTasks.first?.id == createdDTO.id)
    }

    @Test("TaskModelActor toggles completion and filters tasks")
    func testToggleAndFiltering() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task1 = try await actor.addTask(title: "Task A", priority: .low)
        let task2 = try await actor.addTask(title: "Task B", priority: .medium)

        // Verify both pending
        var pending = try await actor.fetchTasks(filter: .pending)
        #expect(pending.count == 2)

        // Toggle task1
        let updatedTask1 = try await actor.toggleTaskCompletion(id: task1.id)
        #expect(updatedTask1?.isCompleted == true)

        // Check filtered queries
        pending = try await actor.fetchTasks(filter: .pending)
        #expect(pending.count == 1)
        #expect(pending.first?.id == task2.id)

        let completed = try await actor.fetchTasks(filter: .completed)
        #expect(completed.count == 1)
        #expect(completed.first?.id == task1.id)
    }

    @Test("TaskModelActor deletes tasks properly")
    func testDeletion() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        let task = try await actor.addTask(title: "To be deleted")
        var tasks = try await actor.fetchTasks(filter: .all)
        #expect(tasks.count == 1)

        try await actor.deleteTask(id: task.id)
        tasks = try await actor.fetchTasks(filter: .all)
        #expect(tasks.isEmpty)
    }

    @Test("TaskListViewModel coordinates with background actor on @MainActor")
    @MainActor
    func testViewModelIntegration() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)
        let viewModel = TaskListViewModel(modelActor: actor)

        #expect(viewModel.tasks.isEmpty)

        // Add task through ViewModel
        await viewModel.addTask(title: "ViewModel Task", note: "MVVM test", priority: .high)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "ViewModel Task")

        // Search text filtering
        viewModel.searchText = "ViewModel"
        #expect(viewModel.displayedTasks.count == 1)

        viewModel.searchText = "NonExistent"
        #expect(viewModel.displayedTasks.isEmpty)

        viewModel.searchText = ""

        // Toggle completion
        if let firstTask = viewModel.tasks.first {
            await viewModel.toggleCompletion(for: firstTask)
            #expect(viewModel.tasks.first?.isCompleted == true)
        }

        // Delete task
        if let firstTask = viewModel.tasks.first {
            await viewModel.delete(task: firstTask)
            #expect(viewModel.tasks.isEmpty)
        }
    }

    @Test("Concurrent actor operations execute without data races")
    func testConcurrentActorOperations() async throws {
        let container = try makeInMemoryContainer()
        let actor = TaskModelActor(modelContainer: container)

        // Launch 20 concurrent tasks calling the background actor
        try await withThrowingTaskGroup(of: TaskItemDTO.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await actor.addTask(title: "Concurrent Task \(i)", priority: .medium)
                }
            }

            var count = 0
            for try await _ in group {
                count += 1
            }
            #expect(count == 20)
        }

        let allTasks = try await actor.fetchTasks(filter: .all)
        #expect(allTasks.count == 20)
    }
}
```

---

## 9. Key Architectural Decisions & Rationale

| Decision | Rationale |
| :--- | :--- |
| **Sendable Value Types (`TaskItemDTO`) for Data Crossing** | Eliminates Swift 6 cross-actor data race compile errors (`sending 'task' risks causing data races`). Protects UI from accessing un-faulted CoreData/SwiftData managed references. |
| **`PersistentIdentifier` as DTO Identity** | Native to SwiftData, conforms to `Sendable`, `Hashable`, and `Identifiable`. Allows the UI to reference persistent entities stably without retaining managed objects. |
| **`@ModelActor` for Persistence Operations** | Provides a dedicated `ModelExecutor` on the cooperative thread pool. Eliminates main-thread database hitches during predicate evaluations and large fetches. |
| **`@Observable` Macro for ViewModel** | Modern replacement for `ObservableObject`. Eliminates `@Published` noise, optimizes view redraws through property-level observation tracking, and integrates naturally with `@MainActor`. |
| **Decoupling Views from `@Query`** | Standard `@Query` embeds database dependencies directly inside the View hierarchy. Moving persistence to the ViewModel and `@ModelActor` ensures clean testability, separation of concerns, and prevents main-thread I/O bottlenecks. |
| **Explicit `nonisolated init` on DTO** | Under Xcode's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, module declarations default to `@MainActor`. Marking the DTO initializer `nonisolated` allows the background `TaskModelActor` to construct DTOs without violating actor isolation. |
| **Static Factory for Previews (`TaskListViewModel.preview`)** | The Xcode `#Preview` macro compiles into a separate preview thunk. Instantiating `@ModelActor` through a static method on the ViewModel avoids initializer visibility bugs in the macro expansion environment. |
| **Swift Testing (`import Testing`)** | Modern, macro-driven testing framework replacing `XCTest`. Native support for async tests (`@Test`), test suites (`@Suite`), and descriptive expectation reporting (`#expect`). |
