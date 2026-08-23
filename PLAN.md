# Swift 6 SwiftData Background Query Architecture with MVVM

This plan details updating the vanilla Xcode project to use **Swift 6 Strict Concurrency** with **SwiftData** background querying using modern macros (`@Observable`, `@Model`, `@ModelActor`) in an **MVVM architecture**.

## Background & Architectural Design

### Avoiding "Sendability Hell" in Swift 6 & SwiftData
In Swift 6 strict concurrency mode:
1. SwiftData `@Model` classes (e.g. `TaskItem`) are **non-Sendable** reference types bound to a specific `ModelContext`.
2. Accessing `@Model` instances across actor boundaries leads to data races and compiler errors under Swift 6 strict concurrency.
3. To safely query data in the background without Sendability violations, we adopt the **Sendable DTO Pattern**:
   - Background querying and data mutations run inside a dedicated `@ModelActor` (`TaskModelActor`) on its isolated context.
   - The actor queries `[TaskItem]` on the background thread and maps them directly into `[TaskDTO]` (a `Sendable` value-type `struct` carrying `PersistentIdentifier` and task properties).
   - Only `Sendable` types (`TaskDTO`, `PersistentIdentifier`, strings, enums) cross the isolation boundary between `TaskModelActor` and `@MainActor TaskListViewModel`.
   - The `@MainActor @Observable` ViewModel consumes the `TaskDTO` list to drive SwiftUI UI reactivity cleanly.

---

## User Review Required

> [!NOTE]
> The project will be updated to enforce **Swift 6 Language Mode** (`SWIFT_VERSION = 6.0`) with strict concurrency checks enabled.

---

## Proposed Changes

### 1. SwiftData Model & Data Transfer Object

#### [NEW] [TaskItem.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskItem.swift)
- Replace template `Item.swift` with `TaskItem.swift`.
- Define `@Model final class TaskItem` with properties:
  - `id: UUID`
  - `title: String`
  - `isCompleted: Bool`
  - `createdAt: Date`
  - `priority: TaskPriority`
- Define `enum TaskPriority: String, Codable, CaseIterable, Sendable`.

#### [DELETE] [Item.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/Item.swift)
- Delete default boilerplate `Item.swift`.

#### [NEW] [TaskDTO.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskDTO.swift)
- Define `struct TaskDTO: Identifiable, Sendable, Hashable, Equatable`:
  - `let id: PersistentIdentifier`
  - `let taskUUID: UUID`
  - `var title: String`
  - `var isCompleted: Bool`
  - `var createdAt: Date`
  - `var priority: TaskPriority`

---

### 2. Background SwiftData Actor

#### [NEW] [TaskModelActor.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskModelActor.swift)
- Uses the `@ModelActor` macro to manage a dedicated background `ModelContext`.
- Methods for asynchronous background database operations:
  - `fetchTasks(predicate: Predicate<TaskItem>?, sortBy: [SortDescriptor<TaskItem>]) throws -> [TaskDTO]`
  - `addTask(title: String, priority: TaskPriority) throws -> TaskDTO`
  - `toggleTask(id: PersistentIdentifier) throws -> TaskDTO?`
  - `deleteTask(id: PersistentIdentifier) throws`
  - `deleteTasks(ids: [PersistentIdentifier]) throws`
  - `seedSampleTasksIfEmpty() throws`

---

### 3. ViewModel Layer

#### [NEW] [TaskListViewModel.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskListViewModel.swift)
- Decorated with `@MainActor` and `@Observable`.
- Owns an instance of `TaskModelActor`.
- Properties:
  - `tasks: [TaskDTO]`
  - `isLoading: Bool`
  - `errorMessage: String?`
  - `searchText: String`
  - `selectedFilter: TaskFilter` (all / active / completed)
  - `selectedPriority: TaskPriority?`
- Methods using `async/await`:
  - `loadTasks()`
  - `addTask(title: String, priority: TaskPriority)`
  - `toggleTaskCompletion(_ task: TaskDTO)`
  - `deleteTask(_ task: TaskDTO)`
  - `deleteTasks(at offsets: IndexSet)`
  - `seedSampleData()`

---

### 4. SwiftUI Views Layer

#### [MODIFY] [ContentView.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/ContentView.swift)
- Replace boilerplate with full task manager UI:
  - Searchable list (`.searchable`)
  - Filter picker (All, Active, Completed)
  - Pull-to-refresh (`.refreshable { await viewModel.loadTasks() }`)
  - Add task toolbar button presenting sheet
  - Empty state and loading indicators
  - Swipe actions for complete and delete

#### [NEW] [AddTaskView.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/AddTaskView.swift)
- Form sheet for adding a new task with title and priority selector.

#### [NEW] [TaskRowView.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskRowView.swift)
- Clean task row view displaying priority badge, title, creation date, and interactive completion checkmark.

---

### 5. App Entry Point & Project Settings

#### [MODIFY] [TaskManagerApp.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager/TaskManagerApp.swift)
- Initialize `ModelContainer` for `TaskItem.self`.
- Inject `ModelContainer` into `ContentView`.

#### [MODIFY] [project.pbxproj](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj/project.pbxproj)
- Update `SWIFT_VERSION` to `6.0`.
- Ensure `SWIFT_STRICT_CONCURRENCY = complete`.

---

### 6. Tests

#### [MODIFY] [TaskManagerTests.swift](file:///Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManagerTests/TaskManagerTests.swift)
- Add Swift Testing suite testing `TaskModelActor` background fetches/mutations and `TaskListViewModel` async flows.

---

## Verification Plan

### Automated Compilation & Concurrency Checks
1. Compile using `xcrun swiftc` targeting iOS Simulator with `-swift-version 6` and `-strict-concurrency=complete`.
2. Run unit tests using `xcodebuild test` / `swift test`.
3. Verify zero Swift 6 concurrency warnings or errors.

### Functional Verification
- Verify background fetching populates the `@Observable` ViewModel.
- Verify adding, completing, and deleting tasks updates UI in real-time.
- Verify search and filtering.
