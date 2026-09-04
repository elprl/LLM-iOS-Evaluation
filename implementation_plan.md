# Swift 6 Strict Concurrency SwiftData Background Query Architecture

This plan modernizes the TaskManager Xcode project to Swift 6 strict concurrency mode with an MVVM architecture that executes SwiftData queries and mutations on a background actor using modern Swift macros (`@Model`, `@ModelActor`, `@Observable`).

## Background & Avoiding "Sendability Hell"

In Swift 6 mode, strict concurrency checking is fully enforced:
- **The Problem**: SwiftData `@Model` classes are reference types bound to a specific `ModelContext` and are **not** `Sendable`. Passing `@Model` instances directly across actor boundaries (e.g., from a `@ModelActor` background worker to a `@MainActor` ViewModel or SwiftUI View) triggers compiler errors: `sending 'task' risks causing data races`.
- **The Solution**: 
  1. Use `@ModelActor` (`TaskModelActor`) to encapsulate all background queries and mutations on its dedicated actor context.
  2. Map fetched `@Model` entities into an immutable `Sendable` value type (`TaskItemDTO`) that carries `PersistentIdentifier` (which conforms natively to `Sendable` and `Hashable`).
  3. Transfer `[TaskItemDTO]` across the actor boundary to the `@MainActor` `@Observable` ViewModel.
  4. Perform mutations (create, toggle, delete) by passing `Sendable` primitives and `PersistentIdentifier`s back to the `@ModelActor`, which looks up the model in its own context, mutates it, and saves.

```
┌─────────────────────────────────────────────────────────────┐
│                      @MainActor                             │
│  ┌───────────────────────┐       ┌───────────────────────┐  │
│  │     ContentView       │ <---> │   TaskListViewModel   │  │
│  │    (SwiftUI View)     │       │     (@Observable)     │  │
│  └───────────────────────┘       └───────────┬───────────┘  │
└──────────────────────────────────────────────┼──────────────┘
                                    async/await│ Sendable DTOs
                                               ▼ & Identifiers
┌─────────────────────────────────────────────────────────────┐
│                   TaskModelActor (@ModelActor)              │
│                        (Background Actor)                   │
│                                                             │
│   • Background Queries (FetchDescriptor<TaskItem>)          │
│   • Converts TaskItem -> TaskItemDTO                        │
│   • ModelContext.save() & CRUD Operations                   │
└─────────────────────────────────────────────────────────────┘
```

## User Review Required

> [!NOTE]
> The Xcode build setting `SWIFT_VERSION` will be upgraded from `5.0` to `6.0` with `SWIFT_STRICT_CONCURRENCY = complete` to ensure full Swift 6 language mode enforcement.

> [!NOTE]
> The existing `Item.swift` will be replaced with `TaskItem.swift` and `TaskItemDTO.swift`, tailored to tasks with titles, priorities, notes, completion status, and due dates.

## Proposed Changes

### Project Build Settings

#### [MODIFY] [project.pbxproj](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj/project.pbxproj)
- Update `SWIFT_VERSION = 6.0;` for all build configurations (`Debug` and `Release` for `TaskManager`, `TaskManagerTests`, `TaskManagerUITests`).
- Ensure `SWIFT_STRICT_CONCURRENCY = complete;` is explicitly configured.

---

### Data Models & DTO Layer

#### [DELETE] [Item.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/Item.swift)
- Replace with `TaskItem.swift` and `TaskItemDTO.swift`.

#### [NEW] [TaskItemDTO.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskItemDTO.swift)
- Define `TaskPriority: Int, Codable, Sendable, CaseIterable, Comparable`.
- Define `TaskItemDTO: Identifiable, Sendable, Hashable`:
  - `id: PersistentIdentifier` (or `UUID` fallback)
  - `title: String`
  - `note: String`
  - `isCompleted: Bool`
  - `priority: TaskPriority`
  - `dueDate: Date?`
  - `createdAt: Date`

#### [NEW] [TaskItem.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskItem.swift)
- `@Model final class TaskItem`:
  - Managed properties matching the domain.
  - Helper method `toDTO() -> TaskItemDTO`.

---

### Background Persistence Layer

#### [NEW] [TaskModelActor.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskModelActor.swift)
- Implement `@ModelActor actor TaskModelActor`:
  - `fetchTasks(filter: TaskFilter, sortBy: TaskSortOption) throws -> [TaskItemDTO]`
  - `addTask(title: String, note: String, priority: TaskPriority, dueDate: Date?) throws -> TaskItemDTO`
  - `toggleTaskCompletion(id: PersistentIdentifier) throws -> TaskItemDTO?`
  - `deleteTask(id: PersistentIdentifier) throws`
  - `deleteTasks(ids: [PersistentIdentifier]) throws`
  - Seed sample tasks if container is empty.

---

### ViewModel Layer

#### [NEW] [TaskListViewModel.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskListViewModel.swift)
- `@Observable @MainActor final class TaskListViewModel`:
  - State: `tasks: [TaskItemDTO]`, `isLoading: Bool`, `errorMessage: String?`, `searchText: String`, `filter: TaskFilter`.
  - Methods using `async/await`:
    - `loadTasks() async`
    - `addTask(title: String, note: String, priority: TaskPriority, dueDate: Date?) async`
    - `toggleCompletion(task: TaskItemDTO) async`
    - `delete(at offsets: IndexSet) async`
    - `delete(task: TaskItemDTO) async`

---

### UI & App Lifecycle

#### [MODIFY] [ContentView.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/ContentView.swift)
- Replace direct `@Query` with MVVM pattern observing `TaskListViewModel`.
- Task list with checkmark toggle, priority badge, due date, swipe to delete.
- Filter segmented control (All, Pending, Completed) and search support.
- Sheet to add new tasks.
- Asynchronous lifecycle via `.task { await viewModel.loadTasks() }` and `.refreshable { await viewModel.loadTasks() }`.
- In-memory preview support.

#### [MODIFY] [TaskManagerApp.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskManagerApp.swift)
- Initialize `ModelContainer` for `TaskItem.self`.
- Inject or initialize `TaskModelActor` and wire up `ContentView`.

---

### Automated Testing

#### [MODIFY] [TaskManagerTests.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManagerTests/TaskManagerTests.swift)
- Add tests verifying background fetch, insert, toggle, and delete via `TaskModelActor` and `TaskListViewModel` on an in-memory `ModelContainer` under Swift 6 concurrency.

## Verification Plan

### Automated Verification
- Build project using `BuildProject` tool to verify zero Swift 6 strict concurrency errors or warnings.
- Run tests via `xcodebuild test` or `RunSomeTests` targeting `TaskManagerTests`.

### Manual Verification
- Check Preview and UI components for full interactivity (adding tasks, toggling completion, filtering, deleting).
