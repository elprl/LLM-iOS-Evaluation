# Architecture

Solution notes for the `claude/opus5-high` branch.

This document explains what was built for the harness prompt, and why each structural
decision was made. It is a description of the code as it currently stands, including the
parts I would change. No code was modified to write this.

---

## 1. The problem the prompt is actually setting

> *Give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query
> in the background using MVVM with `@Observable`, `@Model`, `@ModelActor`. Avoid
> "sendability hell".*

"Sendability hell" is the state you end up in when you try to move SwiftData's types across
isolation domains and the compiler refuses. The three types at the centre of it:

| Type | `Sendable`? | Consequence |
| --- | --- | --- |
| `ModelContainer` | Yes | Safe to share. One instance can back the whole app. |
| `ModelContext` | **No** | Must never leave the actor that created it. |
| `PersistentModel` (`TaskItem`) | **No** | Must never leave the context that owns it. |
| `FetchDescriptor` | **No** | Cannot be built on the main actor and sent to a data actor. |
| `PersistentIdentifier` | Yes | Can travel freely. This is the escape hatch. |

Most attempts fail because people try to make the model types cross the boundary, then reach
for `@unchecked Sendable` when the compiler complains. That silences the error and keeps the
data race.

The architecture below takes the opposite approach: **nothing that SwiftData owns ever
crosses an actor boundary in either direction.** Requests go across as plain values, results
come back as plain values, and identity travels as a `PersistentIdentifier`.

---

## 2. Build configuration

Set on the app target (`project.pbxproj`):

```
SWIFT_VERSION = 6.0
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
IPHONEOS_DEPLOYMENT_TARGET = 26.5
```

**Rationale.**

`SWIFT_VERSION = 6.0` puts the target in Swift 6 language mode, which makes complete
strict-concurrency checking an error rather than a warning. That is the whole point of the
exercise; there is no value in a build that merely warns.

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is kept from the Xcode 26 template rather than
removed. It inverts the default: types are main-actor isolated unless you say otherwise. For
a UI app this is the right default, because the overwhelming majority of types are UI-bound
and annotating each one is noise. The cost is that the small number of types which must
*not* be main-actor now need an explicit `nonisolated`, and forgetting one is a compile
error rather than a silent bug. I would rather be told.

This setting is the reason `nonisolated` appears on `TaskItem`, `TaskSnapshot`, `TaskDraft`,
`TaskQuery`, `TaskStore`, `ModelContainerFactory` and the three enums. Without it,
`TaskDataActor` could not touch any of them off the main actor. It reads like clutter until
you understand the default is inverted.

`SWIFT_APPROACHABLE_CONCURRENCY` enables the SE-0461 family of inference improvements, which
is what allows `nonisolated` on a type declaration to mean "this whole type opts out".

Note that `SWIFT_DEFAULT_ACTOR_ISOLATION` is set on the **app** target only, not on the test
targets. The tests therefore run under normal nonisolated defaults, which is why
`TaskManagerTests` annotates its two view-model tests with `@MainActor` explicitly.

---

## 3. The shape

```
┌──────────────────────────── @MainActor ────────────────────────────┐
│                                                                    │
│   TaskListView ──┬── TaskRowView                                   │
│        │         └── AddTaskView                                   │
│        │                                                           │
│        ▼                                                           │
│   TaskListViewModel  (@MainActor @Observable)                      │
│        │  holds [TaskSnapshot], never TaskItem                     │
│        │                                                           │
└────────┼───────────────────────────────────────────────────────────┘
         │
         │   await  ── TaskQuery / TaskDraft / PersistentIdentifier ──▶
         │   ◀── [TaskSnapshot] / Int ──
         │
┌────────┼──────────────── TaskDataActor's executor ─────────────────┐
│        ▼                                                           │
│   any TaskStore  ◀── protocol seam, all members Sendable-in/out    │
│        │                                                           │
│   TaskDataActor  (@ModelActor)                                     │
│        │  owns a private ModelContext                              │
│        ▼                                                           │
│   TaskItem  (@Model, nonisolated)  ── never leaves this box        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

Everything crossing the middle line is a `Sendable` value type. That is the single rule the
whole design is built around.

---

## 4. Layer by layer

### 4.1 The persisted model

`TaskManager/Models/TaskItem.swift`

```swift
@Model
nonisolated final class TaskItem {
    var title: String
    var details: String
    var isCompleted: Bool
    var createdAt: Date
    var dueDate: Date?

    var urgencyRawValue: Int

    var urgency: TaskUrgency {
        get { TaskUrgency(rawValue: urgencyRawValue) ?? .normal }
        set { urgencyRawValue = newValue.rawValue }
    }
    ...
}
```

**Why `nonisolated`.** Under default-MainActor isolation this class would otherwise be
implicitly `@MainActor`, and `TaskDataActor` could not read or write it. This one keyword is
the difference between the design working and not compiling.

**Why urgency is stored as `Int` with a computed wrapper.** `#Predicate` and `SortDescriptor`
need a key path to a stored, primitive-typed property. SwiftData cannot sort on a computed
property, and a `Codable` enum stored directly is opaque to the predicate machinery. Storing
the raw value keeps `SortDescriptor(\.urgencyRawValue, order: .reverse)` working while the
rest of the codebase uses the typed `urgency`. `@Model` ignores computed properties, so the
wrapper is free.

`urgencyRawValue` is deliberately internal rather than `private` — `TaskQuery` lives in
another file and needs the key path. This is a small encapsulation leak accepted in exchange
for keeping query construction in one place.

### 4.2 The boundary value types

Three separate `Sendable` structs, each answering a different question. Merging them would
be tidier on paper and worse in practice, because they travel in different directions.

**`TaskSnapshot` — results travelling out.**

```swift
nonisolated struct TaskSnapshot: Identifiable, Hashable, Sendable {
    let id: PersistentIdentifier
    let title: String
    ...
    init(_ item: TaskItem) {
        self.id = item.persistentModelID
        ...
    }
}
```

Immutable by design. The view layer cannot mutate it, so there is no way to "accidentally
save" from a view, and no possibility of a snapshot being changed under SwiftUI while a
background context writes.

`id` is the `PersistentIdentifier`, which *is* `Sendable`. This is the key move: the snapshot
carries enough identity to be handed back to the actor later and re-resolved into the real
model, without the model itself ever escaping. `Identifiable` conformance also means `ForEach`
gets stable identity for free.

`Hashable` is what makes `.animation(.default, value: viewModel.tasks)` work in the list.

**`TaskDraft` — new-task data travelling in.**

```swift
nonisolated struct TaskDraft: Hashable, Sendable {
    var title: String = ""
    var details: String = ""
    var dueDate: Date?
    var urgency: TaskUrgency = .normal

    var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
```

The alternative — letting `AddTaskView` build a `TaskItem` and send it over — is exactly the
mistake this architecture exists to avoid. A `TaskItem` constructed on the main actor belongs
to no context, and inserting it into the actor's context from outside is a race. Sending a
draft means the model object is only ever constructed *inside* `TaskDataActor.add(_:)`, on
the context that will own it.

`isValid` lives on the draft rather than in the view or the view model so the same rule
governs the Add button's `disabled` state and the view model's guard, with no chance of the
two drifting apart.

**`TaskQuery` — the request travelling in.**

```swift
nonisolated struct TaskQuery: Hashable, Sendable {
    var searchText: String = ""
    var filter: TaskFilter = .all
    var sortOrder: TaskSortOrder = .dueDate

    func fetchDescriptor() -> FetchDescriptor<TaskItem> {
        FetchDescriptor(predicate: predicate(), sortBy: sortDescriptors())
    }
    ...
}
```

This is the type I consider the most load-bearing decision in the branch.

`FetchDescriptor` is not `Sendable`. Any design where the view model builds a descriptor and
awaits `store.fetch(descriptor)` is dead on arrival under strict concurrency. The usual
workaround is to explode the query into a long parameter list — `tasks(search:filter:sort:)` —
which grows every time a filter is added and forces every conforming type to re-implement
the descriptor logic.

Instead, the view model sends a plain value, and the descriptor is built **on the actor's
side**, where the resulting non-`Sendable` machinery never has to move again. Adding a new
filter dimension is a field on this struct; the protocol never changes.

The `Hashable` conformance earns its keep twice: once for `.task(id:)` in the view, and once
because a value-equal query means "same request", which is what makes cancellation and
debouncing behave sensibly.

Inside `predicate()`:

```swift
let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
let isSearching = search.isEmpty == false
let requiresCompleted = filter == .completed
let requiresActive = filter == .active

return #Predicate<TaskItem> { item in
    (isSearching == false || item.title.localizedStandardContains(search))
        && (requiresCompleted == false || item.isCompleted)
        && (requiresActive == false || item.isCompleted == false)
}
```

`#Predicate` can only capture simple values and cannot contain control flow, so every
decision is unpacked into a local `Bool` first and expressed as `flag == false || condition`.
That pattern reads awkwardly but is the only way to get an optional clause into a single
predicate expression. Building three separate predicates and branching would have been more
readable Swift and worse SwiftData, because the branches would have to be reassembled
somewhere.

`localizedStandardContains` rather than `contains` or `localizedCaseInsensitiveContains`:
it is the only one of the three that is both case- and diacritic-insensitive and respects
the user's locale, which is what a search field should do. The test
`searchMatchesCaseAndDiacriticInsensitively` covers this — `"cafe"` matches `"Café renovation"`.

### 4.3 The data layer

**`TaskStore` — the protocol seam.**

```swift
nonisolated protocol TaskStore: Sendable {
    func tasks(matching query: TaskQuery) async throws -> [TaskSnapshot]
    func count(matching query: TaskQuery) async throws -> Int
    func add(_ draft: TaskDraft) async throws
    func setCompletion(_ isCompleted: Bool, forTaskWith id: PersistentIdentifier) async throws
    func delete(taskWith ids: [PersistentIdentifier]) async throws
    func seedSampleDataIfEmpty() async throws
}
```

**Why a protocol at all.** The view model depends on this, not on `TaskDataActor`. That gives
one testing seam and one preview seam. It also means the persistence choice is a
constructor argument rather than a structural commitment — the app is not welded to SwiftData
at the view-model layer.

**Why `: Sendable` on the protocol.** An `any TaskStore` stored in a `@MainActor` class and
called from an async context has to be `Sendable` or it cannot be captured. Actors get the
conformance automatically, so `TaskDataActor` satisfies it without writing anything.

**Why every member is `async throws` even though the actor's implementations are
synchronous.** The `async` is the actor hop. Declaring it in the protocol means the *caller*
sees the suspension point, which is honest about the cost, and it means a non-actor conforming
type (a mock, a network-backed store) fits the same shape without changing call sites.
Swift satisfies an `async` requirement with a synchronous actor method automatically, so the
implementations stay plain.

**The one thing I would change here.** `PersistentIdentifier` appears in two signatures. That
is a SwiftData type in a protocol that is otherwise persistence-neutral, so the seam is
injectable but not storage-agnostic — a network-backed implementation would have to
manufacture identifiers. A domain-owned `TaskID` wrapper would fix it at the cost of a
translation layer on both sides. For an app of this size the leak was the better trade;
in a real product with more than one backing store it would not be.

**`TaskDataActor` — the `@ModelActor`.**

```swift
@ModelActor
actor TaskDataActor: TaskStore {
    func tasks(matching query: TaskQuery) throws -> [TaskSnapshot] {
        let items = try modelContext.fetch(query.fetchDescriptor())
        return items.map(TaskSnapshot.init)
    }
    ...
}
```

`@ModelActor` synthesises three things: an `init(modelContainer:)`, a
`nonisolated let modelContainer`, and an actor-isolated `modelContext` created from that
container. The container is `Sendable` so passing one in is safe; the context it builds never
leaves the actor.

The `map(TaskSnapshot.init)` on the line after the fetch is the load-bearing line of the
whole file. The conversion happens **before** the return, inside the actor. `[TaskItem]` is
not `Sendable` and would be rejected at the boundary; `[TaskSnapshot]` sails through.

Mutation by identity rather than by object:

```swift
func setCompletion(_ isCompleted: Bool, forTaskWith id: PersistentIdentifier) throws {
    guard let item = self[id, as: TaskItem.self] else { return }
    item.isCompleted = isCompleted
    try modelContext.save()
}
```

`self[id, as:]` is the `@ModelActor` subscript, which re-resolves an identifier against this
actor's own context. It returns an optional, so a stale identifier (the row was deleted while
the user was tapping) returns `nil` and the method does nothing, rather than trapping. The
alternative, `modelContext.model(for:)`, is non-optional and will produce a fault for a
missing object — worse behaviour for the same call site.

`delete(taskWith ids:)` takes an array and issues a single `save()` after the loop, so a
multi-row swipe delete is one transaction rather than N. Partial failure is all-or-nothing,
which is what you want.

**`ModelContainerFactory`.**

```swift
nonisolated enum ModelContainerFactory {
    static let schema = Schema([TaskItem.self])
    static func makeAppContainer() -> ModelContainer { ... }
    static func makePreviewContainer() -> ModelContainer { ... }
}
```

A caseless enum as a namespace, so it cannot be instantiated. One schema definition shared by
the on-disk and in-memory configurations means previews and tests can never drift from
production. `fatalError` on failure is deliberate: a container that will not open means the
app has no data layer, and there is no meaningful recovery to offer a user at launch.

### 4.4 The view model

`TaskListViewModel` is `@MainActor @Observable final class`.

**Why `@Observable` rather than `ObservableObject`.** Per-property observation instead of a
single `objectWillChange` firehose, no `@Published` boilerplate, and views only invalidate on
properties they actually read. `ObservableObject` is legacy at this point.

**Why `@MainActor` is written explicitly when the target already defaults to it.** Redundant
today, correct tomorrow. It states the isolation contract at the declaration where a reader
looks for it, and the type stays correct if the build setting is ever changed.

**State model.**

```swift
enum LoadState: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

private(set) var tasks: [TaskSnapshot] = []
private(set) var state: LoadState = .idle
```

A single enum rather than parallel `isLoading` / `errorMessage` / `hasLoaded` booleans, which
can represent states that cannot happen. `private(set)` on both means the view can read but
only the view model can write — the mutating API is the method surface, not the properties.

The `failed` case carries a `String` rather than an `Error` so the state stays `Equatable`
and `Sendable` without wrapping. The error has already been rendered for display by that
point, so nothing is lost.

**The error binding.**

```swift
private(set) var errorMessage: String?

var isShowingError: Bool {
    get { errorMessage != nil }
    set { if newValue == false { errorMessage = nil } }
}
```

`.alert(isPresented:)` needs a `Binding<Bool>`, but the real state is "is there a message".
The usual fix is `Binding(get:set:)` in the view body, which puts logic in `body` and
re-creates the binding on every render. A computed property with a setter gives SwiftUI a
`$` binding directly, keeps the derivation next to the state it derives from, and — because
the getter reads `errorMessage` — registers the observation dependency correctly.

**The query as a computed property.**

```swift
var query: TaskQuery {
    TaskQuery(searchText: searchText, filter: filter, sortOrder: sortOrder)
}
```

Derived, never stored, so it cannot go stale. `searchText`, `filter` and `sortOrder` are the
three settable properties the view binds to; the query is what falls out of them.

**Loading, cancellation and debounce.**

```swift
func load(_ query: TaskQuery, debounce: Bool = true) async {
    if debounce {
        guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
    }

    if state != .loaded { state = .loading }

    do {
        let snapshots = try await store.tasks(matching: query)
        guard Task.isCancelled == false else { return }

        tasks = snapshots
        state = .loaded
    } catch is CancellationError {
        // Superseded by a newer query — leave the existing results on screen.
    } catch {
        state = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
    }
}
```

Several decisions packed in here.

*Debounce via `Task.sleep` rather than a timer.* The view drives this with `.task(id:)`,
which cancels the previous task when the id changes. A cancelled `Task.sleep` throws, the
`guard` returns, and the superseded fetch never reaches the store. Typing "meeting" issues
one fetch, not seven, and no `Combine`, `Timer` or manual `Task` handle is involved. The
debounce is a consequence of cancellation, not a separate mechanism.

*`if state != .loaded { state = .loading }` rather than always setting `.loading`.* On a
refresh there are already rows on screen. Flipping to `.loading` would tear them down and
show a spinner, which reads as a flicker. Only the first load gets the loading state; later
loads show the spinner as an overlay over the existing list.

*The `Task.isCancelled` check after the await.* Cancellation between the fetch completing and
the assignment would otherwise let a stale result overwrite a fresh one.

*`catch is CancellationError` doing nothing on purpose.* A superseded search is not an error
and must not raise an alert. The empty catch is intentional and commented as such.

**Mutations.**

```swift
private func perform(_ mutation: @Sendable (any TaskStore) async throws -> Void) async {
    do {
        try await mutation(store)
        await load(query, debounce: false)
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Every mutation is add-then-reload, funnelled through one place so error handling and refresh
ordering exist once rather than three times.

The closure takes the store as a **parameter** rather than capturing `self`. That is the
point of the signature: an `@Sendable` closure capturing `self` would drag main-actor state
across the boundary. Passing the store in means the closure captures only the `Sendable`
arguments it needs.

`debounce: false` on the post-mutation reload, because the user just tapped something and
expects it to be immediate — there is nothing to debounce.

**The cost of reload-after-mutate.** Toggling one checkbox refetches the entire list. For a
few hundred rows this is imperceptible and it guarantees the UI matches the store, including
re-sorting and re-filtering the changed row into its correct position. Returning the affected
snapshot and patching the array locally would be cheaper, but then a toggle that should move
a row out of the "Active" filter would leave it visibly stuck. I chose correctness over
efficiency here, and would revisit it at a list size where it mattered.

### 4.5 The views

Three views, split by responsibility rather than by size.

`TaskListView` takes `@Bindable var viewModel` — the view model is *owned* by
`TaskManagerApp` via `@State` and passed down, so it survives view identity changes. Ownership
in the app, bindings in the view, is the `@Observable` idiom.

The fetch trigger:

```swift
.task(id: viewModel.query) {
    await viewModel.load(viewModel.query)
}
```

This is the whole re-fetch mechanism. Search text, filter and sort order all feed `query`;
any change gives a new hash, SwiftUI cancels the running task and starts a new one. No
`onChange` handlers, no manual task cancellation, no debounce timer.

`TaskRowView` takes a `TaskSnapshot` and a callback. It cannot reach persistence even if it
wanted to. The property is named `snapshot` rather than `task` specifically because a
property called `task` shadows SwiftUI's `.task` modifier inside `body` and produces
member-lookup errors that are genuinely hard to read.

`AddTaskView` builds a `TaskDraft` and hands it to a closure. It has no reference to the
view model, the store, or a `ModelContext`, which is why it needs no test setup and no
container to preview.

Both previews use a `private struct …Preview: View` wrapper rather than building objects
inline in `#Preview`. Two reasons: the `init(modelContainer:)` synthesised by `@ModelActor`
is not visible from inside another macro's expansion, and `#Preview` bodies are
`ViewBuilder` contexts where statements are not allowed.

---

## 5. Testing

`TaskManagerTests` has eight Swift Testing cases. The design choice that makes them possible:

```swift
private func makeStore() -> TaskDataActor {
    TaskDataActor(modelContainer: ModelContainerFactory.makePreviewContainer())
}
```

Every test gets its own in-memory container. No shared state, no cleanup, no ordering
dependency, and Swift Testing's default parallel execution is safe.

Coverage is split deliberately:

- Six tests exercise `TaskDataActor` directly — add, filter, search, sort, delete, seed
  idempotence. These are the persistence contract.
- Two tests are `@MainActor` and go through `TaskListViewModel`, exercising the full
  round trip across the actor boundary and back into observable state.

The view-model tests are annotated `@MainActor` explicitly because
`SWIFT_DEFAULT_ACTOR_ISOLATION` is set on the app target only, not the test target.

The protocol seam means a fake store could be injected to test failure and cancellation
paths. It is not currently exercised — see below.

---

## 6. Known gaps

Stated plainly, because an architecture document that only lists wins is not useful.

**1. The actor is constructed on the main actor, so the queries are serialised but not
demonstrably off-main.**

```swift
// TaskManagerApp.init()
_taskListViewModel = State(
    initialValue: TaskListViewModel(store: TaskDataActor(modelContainer: container))
)
```

`@ModelActor` does not get a fresh executor; it inherits the executor of the context that
constructs it. Built inside `TaskManagerApp.init`, which is main-actor isolated, the actor's
work runs on the main thread. Everything still compiles, there are no warnings, and the
`Sendable` boundary is genuinely correct — but the "off the main actor" claim in several of
my own doc comments is not established by this construction.

The fix is to make creation an async boundary, e.g. a `@concurrent` static factory that
returns the actor, awaited before the view model is built. This is the single most important
change I would make, and the one thing the prompt was really testing.

**2. Double load on first appear.** `TaskListView` has both `.task { await viewModel.start() }`
and `.task(id: viewModel.query) { … }`. Both fire on first appearance, so the initial list is
fetched twice with non-deterministic ordering between them. Harmless in practice, wasteful
and untidy in principle.

**3. The failure UI is unreachable.** `listContent` shows `emptyState` only when
`viewModel.isEmpty`, and `isEmpty` is `tasks.isEmpty && state == .loaded`. The `.failed`
branch inside `emptyState` therefore cannot be displayed, and the "Try Again" button is dead
code. The error still surfaces through the alert, so a user is not stranded silently, but the
retry affordance does not exist. `isEmpty` should not gate on `.loaded`.

**4. `IndexSet` in the view-model API.** `delete(at offsets: IndexSet)` mirrors
`ForEach.onDelete` rather than the domain. It couples the view model to a list-index-shaped
caller. Taking `[TaskSnapshot]` or `[PersistentIdentifier]` and letting the view do the
mapping would be cleaner.

**5. Tests are happy-path only.** No failure injection, no cancellation test, no overlapping
load test — despite `TaskStore` existing precisely to make those possible.

**6. Scope.** The prompt said "simply lists tasks". This branch has search, three filters,
four sort orders, due dates, urgency, notes, sample seeding and a modal add flow. Better as
a starting point for a real app; more than was asked for as an answer to the prompt.

---

## 7. File map

```
TaskManager/
├── TaskManagerApp.swift              @main — builds container, actor, view model
├── Models/
│   ├── TaskItem.swift                @Model, nonisolated — the persisted record
│   ├── TaskSnapshot.swift            Sendable value copy — results out
│   ├── TaskDraft.swift               Sendable value — new-task data in
│   ├── TaskQuery.swift               Sendable request — builds FetchDescriptor actor-side
│   ├── TaskUrgency.swift             Int-backed, Comparable
│   ├── TaskFilter.swift              all / active / completed
│   └── TaskSortOrder.swift           dueDate / urgency / created / title
├── Data/
│   ├── TaskStore.swift               Sendable protocol — the DI seam
│   ├── TaskDataActor.swift           @ModelActor — owns the background ModelContext
│   └── ModelContainerFactory.swift   app + in-memory containers, one schema
├── ViewModels/
│   └── TaskListViewModel.swift       @MainActor @Observable — load, debounce, mutate
└── Views/
    ├── TaskListView.swift            list, search, filter, sort, states
    ├── TaskRowView.swift             renders one TaskSnapshot
    └── AddTaskView.swift             produces a TaskDraft

TaskManagerTests/
└── TaskManagerTests.swift            8 Swift Testing cases, in-memory containers
```

---

## 8. Summary of the decisions

| Decision | Rationale |
| --- | --- |
| Default-MainActor isolation kept on | UI app; most types belong on the main actor. Exceptions become compile errors, not silent bugs. |
| `nonisolated` on model and boundary types | Required to opt out of the inverted default so the data actor can touch them. |
| `TaskSnapshot` instead of sharing `TaskItem` | `PersistentModel` is not `Sendable`. Immutable copies cross; models stay put. |
| `PersistentIdentifier` as snapshot `id` | It *is* `Sendable`, so identity travels and the model can be re-resolved actor-side. |
| `TaskQuery` instead of a `FetchDescriptor` parameter | `FetchDescriptor` is not `Sendable`. Building it actor-side keeps the boundary clean and the protocol stable as filters grow. |
| `TaskDraft` instead of sending a built `TaskItem` | The model is only ever constructed on the context that will own it. |
| `TaskStore` protocol seam | One injection point for tests and previews; view model not welded to SwiftData. |
| `async throws` on all protocol members | The `async` *is* the actor hop; makes suspension visible and admits non-actor implementations. |
| `@ModelActor` with a synthesised context | Serialised access to one private `ModelContext` that never escapes. |
| Enum `LoadState` over parallel booleans | Illegal states become unrepresentable. |
| `.task(id: query)` for re-fetch | Cancellation, re-fetch and search debounce from one mechanism. |
| `Task.sleep` debounce inside `load` | Cancellation throws, so superseded searches never reach the store. |
| Reload after every mutation | Guarantees ordering and filtering stay correct; costs a full fetch. |
| Computed `isShowingError` binding | Avoids `Binding(get:set:)` in `body` and keeps derivation next to state. |
| In-memory container per test | Parallel-safe, no shared state, no cleanup. |
