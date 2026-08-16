I'll start by looking at the existing project structure.

Vanilla template confirmed, with file-system-synchronized groups (so new files on disk are picked up automatically). Let me check the toolchain and pull in the SwiftUI best-practices skill before writing.

Now I'll build out the architecture. Starting with the model layer:

`TaskPriority` collides with the standard library's concurrency type. Renaming to `TaskUrgency`:

Those are stale index errors (the new file isn't indexed yet). Continuing with the query descriptor types:

Now the `@ModelActor` — the piece that runs queries off the main actor:

Now the view model:

Now the views:

Let me fix the `task` property shadowing SwiftUI's `.task` modifier, and check target platforms:

iOS-only, so those macOS diagnostics are SourceKit noise. Fixing the row view's `task` name collision:

Now the container factory and app entry point, then removing the template files:

All six build configurations are now Swift 6. Let me build and see what strict concurrency actually says:

Only two real errors, both in previews — missing `import SwiftData`. No concurrency errors:

The `@ModelActor`-generated init isn't visible inside the `#Preview` macro expansion (nested macro limitation). Moving it out of the macro body:

Build succeeds under Swift 6 with zero concurrency diagnostics. Let me clean up the manual `Binding(get:set:)` the review skill flags, then add tests:

Now let me run the tests on a simulator:

All 8 tests pass. Let me verify the app actually runs:

Works. The large nav title is being lost behind the filter inset — switching to an inline title:

Title and sort menu now render. Let me exercise the background query path — tapping the "Active" filter:

Filter re-query works. One last check — toggling completion (write path + reload):

Verified end to end: the toggle wrote on the background actor and the task dropped out of the Active filter after the re-fetch.

## What changed

Replaced the template's `Item`/`ContentView` with a Swift 6 MVVM stack. `SWIFT_VERSION` is now `6.0` across all six build configurations (the target already had `SWIFT_APPROACHABLE_CONCURRENCY` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which I kept).

**Models** — [TaskItem.swift](TaskManager/Models/TaskItem.swift) is the `@Model`, marked `nonisolated` so the default-MainActor setting doesn't pin it to the main actor. [TaskSnapshot.swift](TaskManager/Models/TaskSnapshot.swift) is the `Sendable` value copy, [TaskDraft.swift](TaskManager/Models/TaskDraft.swift) the value used for inserts, and [TaskQuery.swift](TaskManager/Models/TaskQuery.swift) a `Hashable` description of a fetch.

**Data** — [TaskDataActor.swift](TaskManager/Data/TaskDataActor.swift) is the `@ModelActor` that owns a background `ModelContext` and does every fetch and write. It conforms to [TaskStore](TaskManager/Data/TaskStore.swift), a `Sendable` protocol whose members are all `async` — actors get `Sendable` conformance free, so injection stays clean.

**ViewModel** — [TaskListViewModel.swift](TaskManager/ViewModels/TaskListViewModel.swift), `@MainActor @Observable`, holding only snapshots.

**Views** — [TaskListView.swift](TaskManager/Views/TaskListView.swift), [TaskRowView.swift](TaskManager/Views/TaskRowView.swift), [AddTaskView.swift](TaskManager/Views/AddTaskView.swift).

## How it avoids sendability hell

Three rules do all the work:

1. **`PersistentModel` never crosses an actor boundary.** `TaskItem` is created, read, and mutated only inside `TaskDataActor`. The view layer only ever sees `TaskSnapshot` values.
2. **`PersistentIdentifier` is the handle.** It *is* `Sendable`, so the view model sends an id back to the actor, which re-resolves the real model against its own context via `self[id, as: TaskItem.self]`.
3. **`FetchDescriptor` is not `Sendable`, so it's never sent.** The main actor sends a `TaskQuery` value; the actor builds the descriptor on its own side. `ModelContainer` *is* `Sendable`, so one instance backs both the SwiftUI environment and the actor — a `ModelContext` is what must not be shared.

There is no `@unchecked Sendable`, no `nonisolated(unsafe)`, and no `MainActor.run` anywhere.

I deliberately did not use `@Query` — it fetches on the main actor, which is the opposite of what you asked for. The tradeoff is that you lose its automatic live updates, so mutations re-fetch explicitly through `perform(_:)`. Re-fetches on search/filter/sort changes ride on `.task(id: viewModel.query)`, which gives cancellation and a 250 ms search debounce for free.

## Verification

- `xcodebuild` succeeds in Swift 6 language mode with zero concurrency warnings.
- 8 tests in [TaskManagerTests.swift](TaskManagerTests/TaskManagerTests.swift) pass, covering the background fetch, predicate filtering, diacritic-insensitive search, sorting, deletes, and the view model crossing the actor boundary.
- Ran it on the iPhone 17 Pro simulator and confirmed filtering and completion toggles work against the background actor.

One naming note: I named the urgency enum `TaskUrgency` rather than `TaskPriority` because the latter collides with the standard library's concurrency type.