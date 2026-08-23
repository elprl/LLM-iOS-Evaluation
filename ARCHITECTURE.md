# Architecture

This document describes the TaskManager solution on this branch. It is a SwiftUI list of tasks, implemented under **Swift 6 strict concurrency**, with **SwiftData work off the main actor**, using **MVVM** and the macros `@Observable`, `@Model`, and `@ModelActor`.

No application code is described hypothetically: every type below exists in `TaskManager/` as written.

## Goal

The prompt asked for:

- Swift 6 strict concurrency
- A SwiftUI app
- SwiftData queries in the background
- MVVM
- Modern macros: `@Observable`, `@Model`, `@ModelActor`
- A simple task list
- `async`/`await`
- Avoid “sendability hell”

The design that satisfies that prompt is: **the UI never sees a SwiftData model**. Persistence lives on a `@ModelActor`. The view model, isolated to the main actor, holds a `Sendable` snapshot (`TaskDTO`) and talks to the store only with `await`.

## Layers

```
┌─────────────────────────────────────────────┐
│  ContentView  (SwiftUI)                     │
│  Renders [TaskDTO], owns local field state  │
└────────────────────┬────────────────────────┘
                     │ await
┌────────────────────▼────────────────────────┐
│  TaskListViewModel  @MainActor @Observable  │
│  UI state: tasks, isLoading, errorMessage   │
└────────────────────┬────────────────────────┘
                     │ await  (Sendable values only)
┌────────────────────▼────────────────────────┐
│  TaskModelActor  @ModelActor                │
│  Fetch / insert / toggle / delete / save    │
│  Maps TaskItem → TaskDTO before returning   │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│  TaskItem  @Model  (SwiftData, not Sendable)│
│  Lives only inside the actor’s ModelContext │
└─────────────────────────────────────────────┘
```

Composition happens at the app root. `TaskManagerApp` owns the `ModelContainer` and constructs the view model once.

```1:28:TaskManager/TaskManagerApp.swift
import SwiftUI
import SwiftData

@main
@MainActor
struct TaskManagerApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: TaskListViewModel

    init() {
        let schema = Schema([TaskItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.modelContainer = container
            self.viewModel = TaskListViewModel(container: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
```

### Why composition lives in the `App`

`ModelContainer` is `Sendable`. `ModelContext` is not. Building the container at launch and passing the container (not a context) into `TaskListViewModel` is the only hand-off that stays legal under Swift 6. The view model then constructs `TaskModelActor(modelContainer:)`, which is the initializer the `@ModelActor` macro generates.

`.modelContainer(modelContainer)` is still attached to the scene so SwiftData’s environment is available if a future view needs it. The current UI does not use `@Query` or `@Environment(\.modelContext)`. Those APIs run on the main actor and would pull persistence back onto the UI thread, which the prompt forbids.

`@main` plus `@MainActor` on the `App` type matches SwiftUI’s lifetime: the scene graph and the view model both belong on the main actor.

If container creation fails, the process cannot usefully continue. There is no fallback store to show. `fatalError` is therefore the composition-time failure mode, not an in-app error path.

## Persistence model: `TaskItem`

```1:19:TaskManager/TaskItem.swift
import Foundation
import SwiftData

/// A task persisted with SwiftData.
///
/// `@Model` classes are not `Sendable` and never cross actor boundaries here;
/// the `@ModelActor` maps them into the `Sendable` `TaskDTO` first.
@Model
final class TaskItem {
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String, isCompleted: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
```

### Rationale

- **`@Model` class, not a struct.** SwiftData persists reference types that it manages. A value type cannot be the stored entity.
- **Three fields only.** The prompt is a list of tasks. Title is the user-facing identity of a row. `isCompleted` supports toggle. `createdAt` gives a stable reverse-chronological order without extra indexes or sort keys.
- **Never sent across actors.** `@Model` types are bound to a `ModelContext`. Crossing an actor boundary with a live `TaskItem` is the main source of sendability errors. This type stays inside `TaskModelActor`.

`persistentModelID` is not stored as an extra property. SwiftData already provides it; `TaskDTO` copies that identifier when mapping.

## The sendability boundary: `TaskDTO`

```1:22:TaskManager/TaskDTO.swift
import Foundation
import SwiftData

/// A plain, value-type snapshot of a `TaskItem`.
///
/// `TaskItem` is a non-`Sendable` reference type owned by a `ModelContext`, so
/// it cannot be returned from a `@ModelActor` to the main actor. `TaskDTO` is
/// the `Sendable` representation that safely crosses that boundary. `ForEach`
/// renders these, which is also why identity is `PersistentIdentifier`-based.
struct TaskDTO: Identifiable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let isCompleted: Bool
    let createdAt: Date

    init(from item: TaskItem) {
        self.id = item.persistentModelID
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.createdAt = item.createdAt
    }
}
```

### Rationale

This type is the answer to “sendability hell.”

Under Swift 6, a `@ModelActor` method that returns `[TaskItem]` is not isolatable to the caller: `TaskItem` is not `Sendable`. Isolating the actor, wrapping models in `@unchecked Sendable`, or hopping through `MainActor.run` with live models all fight the compiler.

A **value snapshot** with `Sendable` stored properties (`PersistentIdentifier`, `String`, `Bool`, `Date`) can leave the actor with a normal `return`. The view model stores `[TaskDTO]`. The list iterates `TaskDTO`. Mutations send only `PersistentIdentifier` or `String` back in.

`Identifiable` with `id: PersistentIdentifier` (not `title`, not a UUID generated in the DTO) means:

- SwiftUI `ForEach` identity matches the persisted row.
- Toggle and delete can round-trip to `modelContext.model(for:)` without a second lookup key.
- Two tasks with the same title remain distinct.

All properties are `let`. The DTO is a snapshot, not a live object. Completing a task does not mutate the DTO in place; the actor writes the model, then the view model reloads a new array.

Mapping happens **inside** the actor (`TaskDTO(from:)`), while `TaskItem` is still legal to touch. Mapping on the main actor would require sending the model out first, which is the thing this type exists to prevent.

## Background store: `TaskModelActor`

```1:38:TaskManager/TaskModelActor.swift
import Foundation
import SwiftData

/// Performs all SwiftData work off the main actor.
///
/// `@ModelActor` supplies a `modelContext` (backed by an executor the macro
/// creates) plus a `modelContainer`, and generates the initializer. We pass it
/// a `ModelContainer` — which *is* `Sendable` — rather than a `ModelContext`
/// (which is *not*), so nothing non-`Sendable` is handed across the actor
/// boundary.
@ModelActor
actor TaskModelActor {
    func fetchTasks() throws -> [TaskDTO] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let items = try modelContext.fetch(descriptor)
        // Map to Sendable DTOs *before* leaving the actor.
        return items.map { TaskDTO(from: $0) }
    }

    func addTask(title: String) throws {
        modelContext.insert(TaskItem(title: title))
        try modelContext.save()
    }

    func toggleTask(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? TaskItem else { return }
        item.isCompleted.toggle()
        try modelContext.save()
    }

    func deleteTask(id: PersistentIdentifier) throws {
        guard let item = modelContext.model(for: id) as? TaskItem else { return }
        modelContext.delete(item)
        try modelContext.save()
    }
}
```

### Rationale for `@ModelActor`

`@ModelActor` is the SwiftData-provided way to get a `ModelContext` that is confined to an actor’s executor. The macro:

1. Declares the type as an `actor`.
2. Provides `modelContainer` and `modelContext`.
3. Generates `init(modelContainer:)`.

That is the background query the prompt asked for. Manual `actor` plus a context created on the main actor, or `Task.detached` around `modelContext.fetch`, reintroduces isolation bugs. The macro is the supported isolation model.

Methods are synchronous `throws` on the actor. Callers `await` them because crossing into the actor is asynchronous. There is no nested `Task` inside the actor and no completion handlers. That is the `async`/`await` style the prompt asked for, without extra hops.

### Why each operation looks like this

**Fetch** uses `FetchDescriptor` with `createdAt` descending so newest tasks appear first. Sort is a persistence concern, not a view-model `sorted(by:)` after the fact, so the DTO array is already in list order.

**Add / toggle / delete** each `save()` immediately. There is no unsaved in-memory queue. The list is small; durability after every user action is simpler than batching, and the view model always reloads after a successful mutation, so the UI matches disk.

**Lookup by `PersistentIdentifier`.** Toggle and delete do not take a `TaskItem` from the UI. They take the id that came from the DTO. `model(for:)` resolves the live object on this actor’s context. Missing ids are ignored (`guard … else { return }`) rather than thrown: a row that disappeared between render and tap is a no-op, not a crash.

**No `@Query`.** `@Query` is a view property wrapper tied to the main-actor context. Using it would satisfy “SwiftData in SwiftUI” but not “query in the background.”

## View model: `TaskListViewModel`

```1:78:TaskManager/TaskListViewModel.swift
import Foundation
import Observation
import SwiftData

/// The "VM" in MVVM. Isolated to the main actor, it owns the `Sendable`
/// state the view renders and routes every mutation through
/// `TaskModelActor`.
///
/// Because the only state that crosses from the background actor is the
/// `Sendable` `[TaskDTO]`, no non-`Sendable` SwiftData object ever reaches
/// the UI — there is nothing to annotate or wrap to satisfy the compiler.
@MainActor
@Observable
final class TaskListViewModel {
    private(set) var tasks: [TaskDTO] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let store: TaskModelActor

    init(container: ModelContainer) {
        self.store = TaskModelActor(modelContainer: container)
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await store.fetchTasks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTask(_ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await store.addTask(title: trimmed)
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleTask(id: PersistentIdentifier) async {
        do {
            try await store.toggleTask(id: id)
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTasks(at offsets: IndexSet) async {
        do {
            let ids = offsets.map { tasks[$0].id }
            for id in ids {
                try await store.deleteTask(id: id)
            }
            await loadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
extension TaskListViewModel {
    /// A view model backed by an in-memory store, for Xcode previews.
    static func makePreview() -> TaskListViewModel {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return TaskListViewModel(container: container)
    }
}
```

### Rationale for `@MainActor` + `@Observable`

**MVVM split.** The view does not own `TaskModelActor` and does not call SwiftData. The view model is the only object that coordinates loading flags, errors, and the task array.

**`@MainActor`.** All UI state (`tasks`, `isLoading`, `errorMessage`) is main-actor state. SwiftUI reads it on the main actor. Isolating the class makes those assignments legal without `MainActor.assumeIsolated` or `await MainActor.run` after every fetch.

**`@Observable` (Observation), not `ObservableObject`.** The prompt asked for modern macros. `@Observable` plus a stored `var viewModel` in the view is the Observation-era pattern. There is no `@Published`, no `objectWillChange`, no `ObservableObject` conformance.

**`private(set)` on `tasks` and `isLoading`.** Only the view model writes those. The view binds `errorMessage` for the alert dismiss path, so that one property is internally settable.

**Reload after mutate.** There is no incremental array surgery (`tasks.insert`, `tasks[i].isCompleted.toggle` on a DTO). After a successful write, `loadTasks()` fetches a fresh snapshot. That keeps the UI equal to the store, avoids mutating a `let`-field DTO, and avoids cache divergence. The cost is an extra fetch per action, which is acceptable for a small list.

**Trim in the view model, not the actor.** Empty titles are a UI rule. The actor still receives a non-empty `String` and stays a persistence port.

**Delete by `IndexSet`.** SwiftUI’s `onDelete` supplies offsets. The view model maps offsets to ids **before** awaiting deletes, so it does not use a stale index into `tasks` after a concurrent reload. Deletes run sequentially so one failure does not leave a partially applied batch without an error.

**Preview factory.** `makePreview()` uses an in-memory `ModelConfiguration` so `#Preview` does not touch the on-disk store. `try!` is limited to preview construction.

## View: `ContentView`

The view is a renderer and an event source. It holds only `newTaskTitle`, which is typing state and does not belong in the view model.

Lifecycle:

- `.task { await viewModel.loadTasks() }` loads once when the view appears.
- `.refreshable { await viewModel.loadTasks() }` reloads from a pull gesture.

Both are `async` view modifiers calling `async` view-model methods. There is no Combine pipeline.

User actions wrap view-model calls in `Task { await … }` because `Button` and `onDelete` are synchronous. That `Task` inherits the main actor from the view, then `await`s the view model, which `await`s the store. Structured concurrency stays linear: view → view model → actor.

Empty / loading / content are explicit:

- Loading and empty list → `ProgressView`
- Loaded empty list → `ContentUnavailableView`
- Non-empty → `List` of `TaskDTO`

Errors surface through a single alert bound to `viewModel.errorMessage`.

```13:20:TaskManager/ContentView.swift
        .task { await viewModel.loadTasks() }
        .refreshable { await viewModel.loadTasks() }
        .alert("Error", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
```

`viewModel` is a plain stored property, not `@State` or `@StateObject`. The `App` owns the instance; Observation tracks `@Observable` changes without an extra wrapper.

## Concurrency model (how sendability hell is avoided)

| Value | Sendable? | Where it lives |
| --- | --- | --- |
| `ModelContainer` | yes | App → view model → `@ModelActor` init |
| `ModelContext` | no | Only as `TaskModelActor.modelContext` |
| `TaskItem` | no | Only inside `TaskModelActor` methods |
| `TaskDTO` | yes | Actor return value → view model → view |
| `PersistentIdentifier` | yes | DTO id → toggle/delete arguments |
| `String` / `Bool` / `Date` | yes | Copied onto the DTO |

The compiler never has to move a non-`Sendable` reference type between isolation domains. There is no `@unchecked Sendable`, no `nonisolated(unsafe)`, no `assumeIsolated` on models, and no `@Query` on the main actor fighting a background context.

Call chain for a toggle:

1. Main actor: `Button` → `Task { await viewModel.toggleTask(id:) }`
2. Main actor: `try await store.toggleTask(id:)` (suspension, hop to the model actor)
3. Model actor: fetch `TaskItem` by id, toggle, `save()`
4. Main actor: `await loadTasks()`
5. Model actor: fetch, map to `[TaskDTO]`, return
6. Main actor: assign `tasks`

Each hop carries only `Sendable` data.

## What was deliberately not used

| Approach | Why it was not used |
| --- | --- |
| `@Query` in the view | Main-actor SwiftData; not a background query |
| Passing `ModelContext` into the view model | `ModelContext` is not `Sendable` |
| Returning `[TaskItem]` from the actor | Models are not `Sendable` |
| `ObservableObject` / `@Published` | Prompt asked for `@Observable` |
| Optimistic local mutation of DTOs | DTOs are immutable snapshots; store is source of truth |
| Combine / callbacks | Prompt asked for `async`/`await` |
| Shared `ModelContext` between UI and actor | Two contexts on two executors, with live objects crossing, is the sendability problem |

## File map

| File | Role |
| --- | --- |
| `TaskManagerApp.swift` | Container + view-model composition |
| `ContentView.swift` | SwiftUI list, add bar, load/refresh |
| `TaskListViewModel.swift` | Main-actor MVVM state and `await` to the store |
| `TaskModelActor.swift` | Background SwiftData |
| `TaskItem.swift` | Persisted `@Model` |
| `TaskDTO.swift` | `Sendable` snapshot for the UI |

Tests under `TaskManagerTests` are still the Xcode template; they are not part of this architecture.
