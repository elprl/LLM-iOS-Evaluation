# Architecture

TaskManager is a SwiftUI task list that queries and mutates SwiftData **off the main actor**, using Swift 6 strict concurrency and MVVM.

The design has one hard rule: **never send a `@Model` instance across an isolation boundary**. Persistence types stay inside a `@ModelActor`. The UI and view model only ever see a `Sendable` value snapshot (`TaskDTO`). That is how the app stays in Swift 6 complete checking without `@unchecked Sendable`, `nonisolated(unsafe)`, or `Task.detached`.

```
TaskManagerApp
  owns ModelContainer (Sendable)
        │
        ▼
ContentView (@MainActor)
  owns TaskListViewModel via @State
        │  await
        ▼
TaskListViewModel (@MainActor, @Observable)
  holds [TaskDTO] only
        │  await (actor hop)
        ▼
TaskModelActor (@ModelActor, background ModelContext)
  owns TaskItem (@Model)
  maps to / from TaskDTO at the actor boundary
```

A typical load:

1. `ContentView.task` calls `await viewModel.loadTasks()`.
2. The view model, still on the main actor, `await`s `taskActor.fetchTasks()`.
3. Swift hops to `TaskModelActor`'s serial executor. The fetch runs on that actor's `ModelContext`, not the main thread.
4. Each `TaskItem` is mapped to a `TaskDTO` **before** the method returns.
5. The `Sendable` array crosses back to the main actor. The view model assigns `tasks`, Observation invalidates the view, and the list redraws.

Mutations follow the same shape: send primitives or `PersistentIdentifier` in, get a `TaskDTO` (or nothing) out.

---

## Compiler settings

The vanilla template shipped as Swift 5 with approachable concurrency. The app target (and tests) now use:

| Setting | Value | Why |
|---|---|---|
| `SWIFT_VERSION` | `6.0` | Language-mode data-race safety, not warnings you can ignore. |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | Makes the intent explicit even though Swift 6 already implies it. |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | Xcode 26 app default. UI, view models, and global-ish state are main-actor unless opted out. This is the main lever against sendability noise in UI code. |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | Enables `NonisolatedNonsendingByDefault`: an `async` function stays on the caller's actor unless it is an actor method or marked `@concurrent`. The view model's `async` methods therefore do not secretly hop to the cooperative pool. |

Default Main Actor isolation and background SwiftData pull in opposite directions. The resolution is not to turn default isolation off. It is to **opt the persistence types out** with `nonisolated`, and let `@ModelActor` be the one type that is not on the main actor.

---

## Why this architecture

### Why not `@Query` on the view?

The vanilla template fetched with `@Query` and mutated through `@Environment(\.modelContext)`. That is the right default for small, main-thread SwiftData screens. It is the wrong default for this harness:

- `@Query` is main-actor work. A large fetch hitch is a UI hitch.
- `ModelContext` and `@Model` instances are bound to the context that created them. Passing them into a background task is the textbook path into sendability errors.
- The prompt asked for a background query, `@ModelActor`, and MVVM. `@Query` would bypass all three.

### Why MVVM instead of putting logic in the view?

SwiftUI can own this screen with `@Query` and a couple of methods. The view model exists because the prompt asked for MVVM, and because the screen has real async work: load, add, delete, toggle, loading flags, and error presentation.

The view still does view things: layout, local form state (`newTaskTitle`, `isAddingTask`), and bridging synchronous controls into `Task { await ... }`. The view model does not know about alerts or text fields.

### Why `@Observable` instead of `ObservableObject`?

`@Observable` is the current Observation path. `@Published` / `@StateObject` would compile, but they are the legacy stack. The owning view stores the view model in `@State` (reference-type ownership on iOS 17+) and uses `@Bindable` only where a binding is required (`isShowingError`).

### Why a DTO instead of making `TaskItem` `Sendable`?

`@Model` classes are reference types tied to a `ModelContext`. They are not `Sendable`, and pretending they are is the core of "sendability hell":

- Annotating the model `@unchecked Sendable` silences the compiler and races the context.
- Sharing the same model instance with the view and a background actor violates SwiftData's thread confinement.
- Sending the model into `Task.detached` does the same thing with more ceremony.

A struct of `Sendable` fields is the honest boundary. The UI cannot accidentally fault a relationship, hold a faulted object across a hop, or mutate a model the actor no longer owns.

`PersistentIdentifier` is `Sendable` and is the only handle the UI is allowed to send back in for mutations.

### Why `@ModelActor` instead of `Task.detached` + a new `ModelContext`?

`ModelContext` is not thread-safe. A detached task that builds a context, fetches, and returns models is easy to write and easy to get wrong: executor hops, unsaved changes, and models escaping their context.

`@ModelActor` gives a dedicated actor, a dedicated `ModelContext`, and a serial executor tied to that context. All SwiftData use in this app goes through that one actor. Methods can be synchronous `throws` functions; callers still `await` them because they are crossing into the actor. That is the async/await style without marking every persistence method `async` for no reason.

### Why keep default Main Actor isolation?

Turning it off would make `TaskItem` and `TaskDTO` nonisolated by default, which looks simpler on the data layer. It would also re-open sendability diagnostics across every UI type that the Xcode 26 template expected to be main-actor. The cheaper, more realistic app shape is:

- default isolation stays `MainActor` (UI stays quiet)
- persistence types opt out with `nonisolated`
- the model actor is the explicit concurrent island

---

## Layer by layer

### 1. Persistence model — `TaskItem`

```swift
@Model
nonisolated final class TaskItem {
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

**Rationale**

- `@Model` is the SwiftData persistence macro. This is the only type that SwiftData stores.
- `nonisolated` is required under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, `TaskItem` would be main-actor isolated, and `TaskModelActor` could not touch its properties.
- The class is `final` because nothing subclasses it.
- Properties are non-optional stored values. CloudKit is not in play, so the CloudKit "everything optional / no unique constraints" rules do not apply.
- `createdAt` defaults to `.now` so insert sites do not invent timestamps.

`TaskItem` is never imported into a view or view-model stored property. The only reader/writer is `TaskModelActor`.

### 2. Sendable snapshot — `TaskDTO`

```swift
nonisolated struct TaskDTO: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let title: String
    let isCompleted: Bool
    let createdAt: Date
}
```

**Rationale**

- A struct of `Sendable` members is `Sendable` without ceremony. That is the hop type.
- `nonisolated` again opts out of default Main Actor isolation. A main-actor struct cannot be *constructed* on `TaskModelActor` and returned to the view model.
- `Identifiable` lets SwiftUI `ForEach` use `id` without an explicit key path.
- `Hashable` is cheap (all fields already hash) and useful for `Set` membership when deleting.
- Every property is `let`. The UI never mutates a DTO in place; toggle/delete produce a new value from the actor.
- There is no `init(_ item: TaskItem)` on the DTO. That initializer would be `nonisolated` and would take a non-`Sendable` class, which invites calling it from the wrong isolation. Mapping lives on the actor, where the model is already confined.

### 3. Background SwiftData — `TaskModelActor`

```swift
@ModelActor
actor TaskModelActor {
    func fetchTasks() throws -> [TaskDTO] {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(dto(from:))
    }

    func addTask(title: String) throws -> TaskDTO { /* insert, save, map */ }

    func deleteTasks(ids: [PersistentIdentifier]) throws {
        for id in ids {
            guard let item = self[id, as: TaskItem.self] else { continue }
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    func toggleTask(id: PersistentIdentifier) throws -> TaskDTO? { /* lookup, toggle, save, map */ }

    private func dto(from item: TaskItem) -> TaskDTO {
        TaskDTO(
            id: item.persistentModelID,
            title: item.title,
            isCompleted: item.isCompleted,
            createdAt: item.createdAt
        )
    }
}
```

**Rationale**

- `@ModelActor` synthesizes `modelContainer`, `modelExecutor`, `modelContext`, the `init(modelContainer:)`, and the `self[id, as:)` lookup. Those are the APIs this type actually needs.
- The actor's executor is **not** the main actor. `await taskActor.fetchTasks()` is the hop off the UI thread.
- Methods take `String` and `PersistentIdentifier`, never `TaskItem`. Inputs are `Sendable`.
- Methods return `TaskDTO` / `[TaskDTO]`, never `TaskItem`. Outputs are `Sendable`.
- `dto(from:)` is the single mapping site. Fetch, insert, and toggle cannot drift.
- Delete is batched (`ids: [PersistentIdentifier]`) so one user swipe is one actor hop and one `save()`, not N hops.
- Lookup uses the `ModelActor` subscript rather than fetching by predicate. The identifier already uniquely names the row in this container.
- `save()` is explicit after every mutation so the next fetch on this context (and any other context that later fetches the store) sees committed state.
- Methods are `throws`, not `async`. They do not await anything internally. Isolation crossing still requires `await` at the call site, which is the intended API shape.

`ModelContainer` itself is `Sendable`, so constructing `TaskModelActor(modelContainer:)` from a main-actor view model is legal.

### 4. View model — `TaskListViewModel`

```swift
@MainActor
@Observable
final class TaskListViewModel {
    private let taskActor: TaskModelActor

    var tasks: [TaskDTO] = []
    var isLoading = false
    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    init(modelContainer: ModelContainer) {
        taskActor = TaskModelActor(modelContainer: modelContainer)
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await taskActor.fetchTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addTask(title: String) async { /* trim, await actor, insert at 0 */ }
    func deleteTasks(ids: [PersistentIdentifier]) async { /* await actor, remove matching DTOs */ }
    func toggleTask(_ task: TaskDTO) async { /* await actor, replace DTO in place */ }
}
```

**Rationale**

- `@MainActor` is redundant under default isolation and is kept as documentation: this type is UI state, not a data actor.
- `@Observable` tracks `tasks`, `isLoading`, and `errorMessage`. The view does not poll.
- The view model does not import SwiftUI. `Array.remove(atOffsets:)` is a SwiftUI extension; using it would drag SwiftUI into the view model under `MemberImportVisibility`. Delete takes identifiers and uses `removeAll`.
- Draft text for the "New Task" alert stays in the view. That is view state, not domain state.
- `isShowingError` is a `Bool` get/set over `errorMessage` so the view can write `$viewModel.isShowingError` instead of a `Binding(get:set:)` in `body`.
- After a successful add/toggle/delete the in-memory `[TaskDTO]` is updated directly. That avoids a second fetch for a single-row change. Delete failure refetches, because the in-memory list may no longer match the store.
- Add inserts at index `0` because the actor sorts by `createdAt` descending. A newly created task is the newest.
- `TaskModelActor` is stored as a `let`. Actors are `Sendable`; holding one from the main actor is the supported pattern.

The `await`s in this type are the entire concurrency surface the UI needs to know about.

### 5. Composition root — `TaskManagerApp`

```swift
@main
struct TaskManagerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TaskItem.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContainer: modelContainer)
        }
    }
}
```

**Rationale**

- The container is created once at launch. It is `Sendable` and shared.
- The scene does **not** apply `.modelContainer(...)`. That modifier exists to feed `@Query` and `@Environment(\.modelContext)`. This app uses neither. Injecting a main-actor context into the environment would invite the next change to bypass `TaskModelActor`.
- `fatalError` on container failure matches the vanilla template: there is no useful UI without a store.

### 6. View layer — `ContentView` and `TaskRow`

```swift
struct ContentView: View {
    @State private var viewModel: TaskListViewModel
    @State private var isAddingTask = false
    @State private var newTaskTitle = ""

    init(modelContainer: ModelContainer) {
        _viewModel = State(initialValue: TaskListViewModel(modelContainer: modelContainer))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        // List of TaskRow, overlay empty/loading, add/error alerts
        // .task { await viewModel.loadTasks() }
    }
}
```

**Rationale**

- The view receives `ModelContainer` and creates the view model in `init`. That is explicit dependency injection. There is no `bootstrapIfNeeded`, no optional view model, and no environment lookup for the actor.
- `@State` is the correct owner for an `@Observable` class on this deployment target.
- `@Bindable` is scoped to `body` and used only for the error alert binding.
- `newTaskTitle` and `isAddingTask` are view-local. Clearing the field on cancel/add does not belong on the view model.
- `.task` is the structured-concurrency entry point for the initial fetch. It is cancelled with the view.
- Button actions are synchronous (SwiftUI's contract). They call small methods that start a `Task { await viewModel... }`. The `Task` inherits main-actor isolation, so assignments to view-model state after `await` remain on the main actor.
- `deleteTasks(at:)` converts `IndexSet` to `[PersistentIdentifier]` *before* hopping. The actor never sees list offsets, which would be meaningless after a refetch.
- Empty and loading are overlays on a stable `List`, not a root `if/else` that swaps the entire view tree.
- `TaskRow` is a dedicated view, not a `private var row: some View`. It takes a DTO and a toggle closure; it does not take the view model.

```swift
struct TaskRow: View {
    let task: TaskDTO
    let onToggle: () -> Void
    // Button with checkmark / title / date, accessibility label + value + hint
}
```

The row is a `Button`, not `onTapGesture`, so VoiceOver gets a control. The completion glyph is `accessibilityHidden`; the label, value, and hint carry the meaning. Color is not the only completion signal: the symbol changes (`circle` vs `checkmark.circle.fill`) and the title is struck through.

Previews use an in-memory `ModelContainer`, seed two `TaskItem`s on a local `ModelContext`, `save()`, then construct `ContentView`. The view model's actor uses a different `ModelContext` on the same container; the saved rows are visible on first `fetchTasks()`.

---

## Isolation map

| Type | Isolation | Crosses actors as |
|---|---|---|
| `ContentView`, `TaskRow` | Main actor (SwiftUI `View`) | n/a |
| `TaskListViewModel` | `@MainActor` | n/a |
| `TaskModelActor` | its own actor / model executor | n/a |
| `TaskItem` | `nonisolated`, confined to the model actor's context | never |
| `TaskDTO` | `nonisolated`, `Sendable` | the hop type |
| `PersistentIdentifier` | `Sendable` | mutation key |
| `ModelContainer` | `Sendable` | constructor argument |
| `String` / `Bool` / `Date` | `Sendable` | field values |

There is no `@unchecked Sendable`, no `nonisolated(unsafe)`, and no `Task.detached` in the app target.

---

## What this deliberately does not do

**Live SwiftData observation.** There is no `ModelContext.didSave` subscriber and no `@Query`. The list refreshes on appear and after the user's own mutations. A second writer against the same store would not update this screen until the next `loadTasks()`. For a single-window task list that is enough; a multi-window or CloudKit app would need an explicit observation channel that still publishes DTOs, not models.

**Optimistic UI beyond the in-memory array.** Failures set `errorMessage` and, on delete, refetch. There is no operation queue or retry.

**A protocol for the actor.** There is one persistence implementation. A protocol would force `Sendable` requirements onto the abstraction for a harness that does not need a fake.

**`@concurrent` on view-model methods.** Under approachable concurrency, `async` stays on the caller. The hop we want is the actor hop, not a hop to the global pool that would then have to hop again into the actor.

---

## File map

| File | Role |
|---|---|
| `TaskManagerApp.swift` | Creates `ModelContainer`, injects it into the root view. |
| `ContentView.swift` | Task list, add/error alerts, `.task` load, preview container. |
| `TaskRow.swift` | One row. DTO in, toggle out. |
| `TaskListViewModel.swift` | Main-actor UI state. Awaits the model actor. |
| `TaskModelActor.swift` | Background SwiftData. Maps to DTOs. |
| `TaskItem.swift` | `@Model` persisted type. |
| `TaskDTO.swift` | `Sendable` snapshot. |
