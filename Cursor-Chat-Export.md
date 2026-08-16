# SwiftUI concurrency implementation
_Exported on 16/08/2026 at 20:10:48 BST from Cursor (3.16.17)_

---

**User**

Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.

---

**Cursor**

I'll start by reading the concurrency and SwiftUI skills, then inspect the current Xcode project so we can wire Swift 6 strict concurrency, SwiftData, and MVVM correctly.

The glob still shows the vanilla template. I’ll read the current Swift files and concurrency references next so we can replace it with a strict-concurrency MVVM SwiftData setup.

The vanilla project is still on Swift 5 with `@Query` on the main actor. I’ll switch it to Swift 6, keep queries on a `@ModelActor`, and pass `Sendable` DTOs into an `@Observable` view model so we never send models across isolation.

The first build failed on missing imports under Member Import Visibility. I’ll pull the actual compiler errors and fix them.

The project now uses **Swift 6 complete concurrency**, MVVM, and background SwiftData without sending `@Model` instances across actors. The app target builds cleanly.

**How sendability stays simple:** `@Model` types are not `Sendable`. The `@ModelActor` maps them to a `TaskDTO` value type before anything returns to the UI. The view model only ever holds those DTOs, so `await` hops stay legal and you never need `@unchecked Sendable`.

```
View (@MainActor)
  → TaskListViewModel (@Observable, @MainActor)
    → await TaskModelActor (@ModelActor, background ModelContext)
      → TaskItem (@Model, nonisolated)
      → returns TaskDTO (Sendable struct)
```

**What changed**

- **Swift 6** with `SWIFT_STRICT_CONCURRENCY = complete`, keeping the Xcode 26 Main Actor default so UI code stays quiet.
- **`TaskItem`** is `nonisolated` so it can live on the model actor instead of the main actor.
- **`TaskModelActor`** owns the `ModelContext` and does fetch/insert/delete/toggle off the main thread. Callers `await` those methods.
- **`TaskListViewModel`** is `@MainActor @Observable`. It never touches SwiftData models.
- **`ContentView`** owns the view model via `@State`, loads with `.task`, and lists tasks.

`@Query` is gone on purpose: it runs on the main actor. Queries now go through the model actor instead.

