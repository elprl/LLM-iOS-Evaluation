# Evaluation of LLM and Agent Capabilities for iOS App Development

## Purpose

This is a LLM evaluation project for testing AI models and agents against a specific prompt that wants to build a reasonably complex SwiftUI app. The goal is to see how well the model/agent can follow the prompt and build the app to the best of its ability for the purpose of comparing the different outputs.

## The Prompt

*Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.*

## Why this prompt?

This prompt is a good test of the model/agent's ability to follow a specific prompt and build a reasonably complex SwiftUI app. It is also a good test of the model/agent's ability to use modern Swift features like Swift 6 strict concurrency, SwiftData, and SwiftUI. It is a simple prompt that hides some threading complexity that is easy to miss when building the app manually. The model must use knowledge and reasoning to build the app.

## The Starting Point

The starting point is a vanilla Xcode project that is the default starting project for a SwiftUI app when one creates a new project in Xcode v26.6. It is a good starting point because it is a simple app that is easy to understand and modify. It is also a good starting point because it is a good example of a SwiftUI app that uses SwiftData.

## The Follow-up Prompt

Describe your solution and architecture in an ARCHITECTURE.md in the root of the project. Copy as much of the relevant code snipets as you need. Do not change any code. Describe your rational for all architectural decisions.

## The Environment

- Xcode 26.6
- Branch 'vanilla' is the starting point.
- I run the prompt against the model/agent and commit the output to the branch only.
- I edit the README.md with environment specific details and setup.

## The Output Branches

In order not to contaminate the results of subsequent model/agent's outputs (and to prevent cheating), I am not consolidating outputs and adding folders into `master`. Instead, I isolate the outputs to their own branch for each model/agent.

- Branch `codex/chatgpt5.6-sol-high` is the outputbranch for the `ChatGPT 5.6 High` model running on Codex Desktop Agent Version 26.810.52044.
- Branch `claude/opus5-high` is the output branch for the `Claude Opus 5 High` model running on Claude Code Agent v1.3.
- Branch `qwen/qwen3.8-27b` is the output branch for the `Qwen 3.8 27B` model running on LM Studio Bionic v1.0.7 and OpenCode v1.18.18.
- Branch `cursor/grok4.6-high` is the output branch for the `Grok 4.6 High` model running on Cursor v3.16.17.

## Comparison of the Output Branches

Codex is the only branch that creates its `@ModelActor` from an `@concurrent` function. That is the executor-affinity trap sitting inside "run a SwiftData query in the background," and everyone else missed it. Claude has the nicest architecture and by far the best tests, but it never proves the work leaves the main thread, and it built a much bigger app than the prompt asked for. Grok is the tidy compact one after Codex, with the best incremental updates and row accessibility, still no real tests, same actor-construction bug. Qwen got the MVVM and Sendable-boundary idea, then dropped the ball on tests, efficiency, accessibility, and layering.

They all managed to figure out the DTO pattern for solving the actor boundary problem, which a year ago even the frontier models were not able to do. Now even a local model has the reasoning ability to do it. This is a huge step forward in the capabilities of local LLMs. `google/gemma-4-31b-qat` was able to work this out, yet `google/gemma-4-26b-a4b-qat` was not. Interesting that none of the models used the `PersistentIdentifier` pattern which reconstitutes the SwiftData object in the main actor context, mentioned in my repo: [https://github.com/elprl/SwiftDataSwift6Concurrency](https://github.com/elprl/SwiftDataSwift6Concurrency) . 

Ranking I would use:

| Rank | Branch                      | Score  | Why                                                   |
| ---- | --------------------------- | ------ | ----------------------------------------------------- |
| 1    | `codex/chatgpt5.6-sol-high` | 8.5/10 | Hits the prompt and gets the concurrency right        |
| 2    | `claude/opus5-high`         | 8.0/10 | Best structure and tests; misses the executor detail  |
| 3    | `cursor/grok4.6-high`       | 6.8/10 | Lean and efficient; untested, not actually background |
| 4    | `qwen/qwen3.8-27b`          | 5.5/10 | Right skeleton, most of the production gaps           |


### How this was scored

The point is whether each model noticed the threading complexity hiding in the prompt. I weighted it that way:

| Criterion                               | Weight |
| --------------------------------------- | ------ |
| Prompt fidelity and correctness         | 30%    |
| Architecture and isolation design       | 20%    |
| Testability and committed tests         | 15%    |
| Maintainability and readability         | 15%    |
| Persistence and state-update efficiency | 10%    |
| UX and accessibility                    | 10%    |


### The concurrency issue that decides this

All four branches land on the same safe data path:

```text
@Model entity
    → @ModelActor persistence layer
    → immutable Sendable snapshot/DTO
    → @MainActor @Observable view model
    → SwiftUI view
```

Nobody hands a live SwiftData model or a `ModelContext` across isolation domains. That part is fine. Actor isolation is not the same as background execution, though. `@ModelActor` serializes access. If you construct it from a main-actor initializer, you have not put SwiftData on an off-main executor.

Codex is the only one that treats creation as an async boundary:

```swift
@concurrent
static func make(modelContainer: ModelContainer) async -> TaskRepository {
    TaskRepository(modelContainer: modelContainer)
}
```

Claude builds `TaskDataActor` in `TaskManagerApp.init`. Grok and Qwen build `TaskModelActor` in their `@MainActor` view-model inits. Their DTO boundaries still look data-race-safe. Their comments about queries running off the main actor are not backed by how the actor is born.

That is why Codex wins this harness even though Claude's architecture is more grown-up.

### Scorecard


| Branch | Correctness | Architecture | Tests | Maintainability | Efficiency | UX/accessibility |
| ------ | ----------- | ------------ | ----- | --------------- | ---------- | ---------------- |
| Codex  | 9.5         | 8.5          | 7.5   | 9.0             | 7.0        | 8.0              |
| Claude | 6.5         | 9.5          | 9.5   | 8.0             | 6.5        | 9.0              |
| Grok   | 6.5         | 7.5          | 2.0   | 8.5             | 9.0        | 8.5              |
| Qwen   | 6.0         | 6.5          | 2.0   | 6.5             | 5.5        | 6.0              |


These are judgments for this prompt, not a ranking of the models in general.

### Codex Sol 5.6 High: the actual answer

Codex has the mix I wanted: correct, small, readable.

It is the only `@concurrent` factory. Swift 6 and complete strict-concurrency checking are set on app and test configs. `TaskEntity` is `nonisolated`; only immutable `TaskSnapshot: Sendable` values leave the repository. The view model is `@MainActor @Observable` and owns the UI state. `beginMutation()` stops overlapping writes from stacking. Initial load checks cancellation after the fetch before publishing. The add field clears only after persistence succeeds. Two real tests cover repository CRUD and the main-actor view-model path with in-memory containers. And it is the size of an app that "simply lists tasks."

What I would still change: the view model takes a `ModelContainer` and builds a concrete repository, so there is no Claude-style injectable store and no fake-store tests. Every mutation refetches the whole list. `deleteTasks(ids:)` fetches every entity and filters in memory. The tests are happy-path, not failure, cancellation, or overlap. If the first load fails, dismissing the alert leaves you on the ordinary empty view with no retry. Error message and visibility are separate pieces of state and can drift.

The full-store delete scan is a coding choice, not a law of UUID identity. A predicate, an index, or a targeted delete API would keep domain IDs without walking every row.

### Claude Opus 5 High: the app I would actually keep

Claude is the most complete design in the set, and it shows.

`TaskStore: Sendable` is the only real dependency-injection seam among the four. `TaskDraft`, `TaskQuery`, and `TaskSnapshot` are good Sendable boundary types. `FetchDescriptor` stays inside the actor via `TaskQuery`, so nobody tries to send non-Sendable query machinery across actors. Folders match the layers. Search, filters, sorting, due dates, urgency, loading, failure, retry, and empty states make the richest UI. Eight tests cover CRUD, filtering, search, sorting, seeding, validation, and the view model. Most comments explain a decision instead of narrating the next line.

Then the miss: `TaskDataActor` is constructed in the main-actor app initializer, so the branch does not do the background-executor thing it keeps claiming. `.task(id: viewModel.query)` and `.task { viewModel.start() }` both start loading on first appear, so you get duplicate work and messy ordering. The failure UI is effectively dead: `emptyState` only shows when `state == .loaded`, and that is also where the `.failed` switch lives. Mutations reload the whole list. The protocol leaks `PersistentIdentifier`, so it is injectable but not persistence-neutral. Search, filters, sort, notes, urgency, due dates, sample seeding, and about three times the code of the leaner branches is more than "simply lists tasks." Some comments talk about background work as if the construction bug were not there.

Give Claude a concurrent actor factory and clean up the double-load, and it would be the best starting point for a real product. For this harness, the executor miss and the extra scope keep it behind Codex.

### Cursor / Grok 4.6 High: small, fast, untested

After Codex, this is the best code-per-feature ratio.

Files are small and split in the right places, including a dedicated `TaskRow`. `TaskItem` stays on the actor; `TaskDTO: Sendable` crosses to the view model. Add and toggle return the affected DTO. Delete batches and saves once. After a successful mutation the view model patches the local array instead of refetching. The row has the best accessibility: label, value, hint, and a decorative icon that is hidden. Swift 6, complete checking, approachable concurrency, and main-actor defaults are all explicit.

`TaskModelActor` is still created inside the `@MainActor` view-model init, so the "background executor" claim is not established. Tests are the vanilla placeholder. `tasks`, `isLoading`, and `errorMessage` have open setters. The view model is glued to a concrete actor, so no fake store. No cancellation or overlapping-load coordination. Inserting at index zero copies the store's newest-first order; change sort rules and the UI and store drift. The add field clears before persistence succeeds. The actor call is awaited, then the local array changes. Incremental post-success updates. Still cheap. Not optimistic UI.

### Local Model / Qwen 3.8 27B: free, the shape is right, but the details are not

Qwen is easy to follow and it did get the idea. The big deal here is that it is a local model, it is free, it built a working app via OpenCode Agent, but it took almost 2 hours to run on my M1 Max Macbook Pro which is unproductive. This is by far the best local coding model I have seen so far as of August 2026. 

`@Model`, `@ModelActor`, a Sendable DTO, an explicit `@MainActor @Observable` view model, async/await all the way down. Live models do not reach the view. Loading, empty, refresh, add, toggle, swipe-delete are all there. `private(set)` protects the task and loading collections. Compact enough to teach from.

Same actor-construction problem as Grok and Claude. Tests still vanilla. Multi-delete does one actor hop and one `save()` per item, then reloads everything, so a later failure can leave a partial write. Every mutation reloads. Concrete actor, no fake store. `IndexSet` leaks into the view-model API. `ContentView` builds rows inline instead of extracting a view. A hand-rolled `Binding(get:set:)` pokes view-model error state. Image-only add and completion controls have no real accessibility labels. Preview helper uses `try!`. Lookups go through `modelContext.model(for:)`, which is non-optional, then silently return if the cast fails. Claude and Grok's typed optional `@ModelActor` subscript is clearer.

Qwen also removed the template's main-actor-by-default setting. Potentially weaker data-race safety. Swift 6 strict checking plus explicit `@MainActor` on the UI can still be a valid design. The fairer complaint is that it leaves the Xcode default and makes every future UI-bound type more work to annotate and review.

### Category winners

| Category                     | Winner | Why                                                             |
| ---------------------------- | ------ | --------------------------------------------------------------- |
| Prompt fulfillment           | Codex  | Only explicit off-main actor construction; stayed small         |
| Concurrency design           | Codex  | `@concurrent` factory, Sendable snapshots, cancellation guard   |
| Architecture and flexibility | Claude | Protocol seam and typed request/draft/snapshot types            |
| Testability and test breadth | Claude | Eight focused tests and an injectable store                     |
| Code-to-value ratio          | Grok   | Small, readable, efficient mutations                            |
| Persistence efficiency       | Grok   | Single-item returns, batched delete, local post-success updates |
| UX breadth                   | Claude | Search, filter, sort, richer add flow, more states              |
| Row accessibility            | Grok   | Label, value, hint, decorative image handled                    |


### If I had to ship one

Unchanged: Codex.

If I were assembling a production version I would steal Codex's `@concurrent` factory, strict settings, mutation gating, and small scope; Claude's `TaskStore` seam, Sendable query object, state model, and tests; and Grok's targeted mutation returns, batched delete, and row accessibility. That would actually run the query in the background and still be something you could extend.

## How you can use this repo to evaluate your own models

1. Clone this repo.
2. Checkout the `vanilla` branch.
3. Create a new branch for your model.
4. Run the PROMPT.md file to generate the output.
5. Commit the output to the new branch.
6. Create a pull request 