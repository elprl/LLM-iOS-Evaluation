# Add Swift 6 task concurrency

> Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.

<details><summary>14 previous messages</summary>

> I’m using the Swift Concurrency and SwiftUI review skills because this touches Swift 6 isolation, SwiftData actors, Observation ownership, and view composition. I’ll first inspect the vanilla project and its deployment settings, then implement the task list end to end and verify it with the project’s own build/test tooling.
>
> <details><summary>Explored a file, a list, ran a command</summary>
>
> <details><summary>Explored 3 files, a list</summary>
>
> - Read `~/.codex/RTK.md`
> - Read `~/.codex/skills/swift-concurrency-expert/SKILL.md`
> - Read `~/.agents/skills/swiftui-pro/SKILL.md`
> - Listed files
>
> </details>
>
> - Ran `rtk proxy sh -c 'cat /Users/paulleo/.codex/skills/swift-concurrency-expert/references/swift-6-2-concurrency.md; cat /Users/paulleo/.codex/skills/swift-concurrency-expert/references/approachable-concurrency.md; cat /Users/paulleo/.codex/skills/swift-concurrency-expert/references/swiftui-concurrency-tour-wwdc.md; cat /Users/paulleo/.agents/skills/swiftui-pro/references/data.md; cat /Users/paulleo/.agents/skills/swiftui-pro/references/swift.md; cat /Users/paulleo/.agents/skills/swiftui-pro/references/views.md; cat /Users/paulleo/.agents/skills/swiftui-pro/references/accessibility.md'`
>
> </details>
>
> The workspace’s RTK wrapper is not installed in this shell, so I’m continuing with the underlying read-only commands. The project is the standard SwiftData template; I’m checking its concurrency build flags and the exact generated model/container structure before replacing it.
>
> <details><summary>Ran a command</summary>
>
> - Ran `cat /Users/paulleo/.codex/skills/swift-concurrency-expert/references/swift-6-2-concurrency.md /Users/paulleo/.codex/skills/swift-concurrency-expert/references/approachable-concurrency.md /Users/paulleo/.codex/skills/swift-concurrency-expert/references/swiftui-concurrency-tour-wwdc.md /Users/paulleo/.agents/skills/swiftui-pro/references/data.md /Users/paulleo/.agents/skills/swiftui-pro/references/swift.md /Users/paulleo/.agents/skills/swiftui-pro/references/views.md /Users/paulleo/.agents/skills/swiftui-pro/references/accessibility.md`
>
> </details>
>
> The concurrency design will use three clean boundaries: `@Model` only inside SwiftData, a `@ModelActor` repository that performs fetches/inserts/deletes off the main actor, and immutable `Sendable` task snapshots returned to a main-actor `@Observable` view model. That avoids passing live SwiftData models or contexts across actors—the usual source of “sendability hell.”
>
> <details><summary>Ran 7 commands</summary>
>
> - Ran `cat /Users/paulleo/.agents/skills/xcodebuildmcp-cli/SKILL.md && git status --short && sed -n '1,260p' TaskManager.xcodeproj/project.pbxproj && for file in TaskManager/*.swift TaskManagerTests/*.swift TaskManagerUITests/*.swift README.md; do echo "--- $file"; sed -n '1,260p' "$file"; done`
> - Ran `command -v xcodebuildmcp || true
> xcodebuildmcp --help 2>/dev/null | sed -n '1,180p'
> printf '\n--- build settings in project ---\n'
> rg -n 'SWIFT_|IPHONEOS_DEPLOYMENT_TARGET|SDKROOT|PRODUCT_BUNDLE|GENERATE_INFOPLIST' TaskManager.xcodeproj/project.pbxproj
> printf '\n--- git ---\n'
> git status --short --branch`
> - Ran `brew --version && brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp`
> - Ran `xcodebuildmcp --help
> xcodebuildmcp tools | sed -n '1,240p'
> printf '\n--- possible SwiftData interfaces ---\n'
> rg --files /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs | rg 'SwiftData.*swiftinterface$' | head -20`
> - Ran `xcodebuildmcp simulator build --help
> xcodebuildmcp project-discovery show-build-settings --help
> printf '\n--- ModelActor declarations ---\n'
> rg -n -A80 -B20 'protocol ModelActor|DefaultSerialModelExecutor|macro ModelActor' /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/SwiftData.framework/Modules/SwiftData.swiftmodule/arm64-apple-ios-simulator.swiftinterface | sed -n '1,320p'`
> - Ran `xcodebuildmcp setup --help
> xcodebuildmcp simulator list --help
> xcodebuildmcp project-discovery discover-projects --help`
> - Ran `find . -maxdepth 3 -path '*/.xcodebuildmcp/*' -o -name '.xcodebuildmcp' -print 2>/dev/null
> find /Users/paulleo -maxdepth 3 -path '*/.xcodebuildmcp/config.yaml' -print 2>/dev/null | head -20`
>
> </details>
>
> The project already opts into approachable concurrency and main-actor-by-default, but it is still compiled in Swift 5 mode. I’m now switching every target to Swift 6 with complete strict-concurrency checking, and replacing the template’s main-context `@Query` with a background-created `@ModelActor` plus sendable value snapshots.
>
> <details><summary>Created 10 files, edited a file, deleted 4 files, ran 2 commands</summary>
>
> - Deleted `./TaskManager/Item.swift` (+0 -18)
> - Wrote `./TaskManager/TaskEntity.swift` (+22 -0)
> - Wrote `./TaskManager/TaskListViewModel.swift` (+94 -0)
> - Wrote `./TaskManager/TaskRepository.swift` (+56 -0)
> - Wrote `./TaskManager/TaskRepositoryError.swift` (+12 -0)
> - Wrote `./TaskManager/TaskRepositoryFactory.swift` (+10 -0)
> - Wrote `./TaskManager/TaskRowView.swift` (+29 -0)
> - Wrote `./TaskManager/TaskSnapshot.swift` (+8 -0)
> - Deleted `./TaskManager/ContentView.swift` (+0 -61)
> - Deleted `./TaskManager/TaskManagerApp.swift` (+0 -32)
> - Deleted `./TaskManagerTests/TaskManagerTests.swift` (+0 -19)
> - Wrote `./TaskManager.xcodeproj/project.pbxproj` (+12 -6)
> - Wrote `./TaskManager/ContentView.swift` (+120 -0)
> - Wrote `./TaskManager/TaskManagerApp.swift` (+26 -0)
> - Wrote `./TaskManagerTests/TaskManagerTests.swift` (+53 -0)
> - Ran `git diff --check
> git status --short
> rg -n 'SWIFT_(VERSION|STRICT_CONCURRENCY|DEFAULT_ACTOR_ISOLATION|APPROACHABLE_CONCURRENCY)' TaskManager.xcodeproj/project.pbxproj
> xcodebuildmcp project-discovery discover-projects --workspace-root /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager --scan-path /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager --max-depth 2 --output text
> xcodebuildmcp project-discovery list-schemes --project-path /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj --output text
> xcodebuildmcp simulator list --enabled true --output text`
> - Ran `xcodebuildmcp simulator build --project-path /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj --scheme TaskManager --simulator-id 085A6A8C-D8E3-4503-9ACC-FD69AB1B7A13 --configuration Debug --output text`
>
> </details>
>
> The first strict build reached the new code and found one preview-only access-control issue: the preview macro expands outside `ContentView`’s private scope. I’m widening that single static container to `fileprivate`, then rebuilding; no concurrency diagnostics have appeared so far.
>
> <details><summary>Edited a file, ran 2 commands</summary>
>
> - Wrote `./TaskManager/ContentView.swift` (+1 -1)
> - Ran `xcodebuildmcp simulator build --project-path /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj --scheme TaskManager --simulator-id 085A6A8C-D8E3-4503-9ACC-FD69AB1B7A13 --configuration Debug --output text`
> - Ran `xcodebuildmcp simulator test --help
> xcodebuildmcp simulator test --project-path /Users/paulleo/Work/tapdigital/TestHarnesses/TaskManager/TaskManager.xcodeproj --scheme TaskManager --simulator-id 085A6A8C-D8E3-4503-9ACC-FD69AB1B7A13 --configuration Debug --output text`
>
> </details>
>
> The app now builds cleanly under Swift 6 complete checking. The full scheme test is still running on the simulator (it includes the generated UI test targets as well as the new repository/view-model tests); I’m waiting for its result, then I’ll do a final diff and warning check.
>
> <details><summary>Ran a command</summary>
>
> - Ran `git diff --check
> printf '\n--- warnings/errors in latest logs ---\n'
> rg -n -i 'warning:|error:' /Users/paulleo/Library/Developer/XcodeBuildMCP/workspaces/TaskManager-ad04a2c387a9/logs/build_sim_2026-08-16T19-47-18-150Z_pid26241_5174389a.log /Users/paulleo/Library/Developer/XcodeBuildMCP/workspaces/TaskManager-ad04a2c387a9/logs/test_sim_2026-08-16T19-47-27-550Z_pid26325_99b2ea32.log || true
> printf '\n--- diff stat ---\n'
> git diff --stat
> printf '\n--- project diff ---\n'
> git diff -- TaskManager.xcodeproj/project.pbxproj TaskManager TaskManagerTests | sed -n '1,1200p'
> printf '\n--- pre-existing README diff ---\n'
> git diff -- README.md`
>
> </details>
>
> Verification is complete: the strict Swift 6 build succeeds and the full scheme passes all 5 tests. The only build-log warnings are Xcode’s harmless “AppIntents metadata skipped” messages because this app does not link AppIntents; there are no Swift or concurrency warnings. I also confirmed the pre-existing README edit remains untouched.
>
> <details><summary>Ran a command</summary>
>
> - Ran `rg -n '@Model|nonisolated final class|@ModelActor|func fetchTasks|@concurrent|@Observable|final class TaskListViewModel|struct ContentView|SWIFT_STRICT_CONCURRENCY|SWIFT_VERSION = 6.0|repositoryPerformsCRUD|viewModelOwns' TaskManager TaskManagerTests TaskManager.xcodeproj/project.pbxproj
> git status --short`
>
> </details>
</details>

Implemented the Swift 6 MVVM task app with background SwiftData access.

Key pieces:

- [`@Model` task entity](./TaskManager/TaskEntity.swift:4)
- [Background-created `@ModelActor` repository](./TaskManager/TaskRepository.swift:4)
- [`@concurrent` repository factory](./TaskManager/TaskRepositoryFactory.swift:6)
- [Immutable `Sendable` snapshots](./TaskManager/TaskSnapshot.swift:3), so live SwiftData models never cross actor boundaries
- [Main-actor `@Observable` view model](./TaskManager/TaskListViewModel.swift:5)
- [Async SwiftUI task list](./TaskManager/ContentView.swift:4)
- [Swift 6 complete strict-concurrency settings](./TaskManager.xcodeproj/project.pbxproj:420)
- [Repository and MVVM tests](./TaskManagerTests/TaskManagerTests.swift:8)

Validation:

- Debug simulator build: passed
- Full scheme: 5 tests passed
- No Swift or concurrency warnings
- Only harmless AppIntents metadata-skip warnings

The concurrency and SwiftUI guidance shaped the explicit actor boundaries, main-actor UI state, and one-type-per-file organization. I also installed the required `xcodebuildmcp` CLI through Homebrew for verification. The pre-existing README modification was preserved untouched.
