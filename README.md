# LLMTestHarness-TaskManager

This is a test harness for the LLMTestHarness project. It is a simple project that allows you to test the LLMTestHarness project.

## The Prompt

```bash
Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.
```
## This `codex/chatgpt4.6-sola-high` branch

This branch is for the `codex/chatgpt4.6-sola-high` model's response to the prompt.

## Environment

- Xcode 26.6
- Swift 6
- Vanilla Xcode project branched from 'vanilla' - the starting point.
- Codex Desktop Agent Version 26.810.52044 running the prompt against the `ChatGPT 4.6 Sol-A High` model. Full access mode only, no plan mode used.
- Skills enabled:
  - Swift Concurrency Expert
  - SwiftUI-pro
  - Swiftui-view-refactor
  - xcodebuildingmcp-cli
  - ios-unit-test-skill
  - RTK