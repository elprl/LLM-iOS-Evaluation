# LLMTestHarness-TaskManager

This is a test harness for the LLMTestHarness project. It is a simple project that allows you to test the LLMTestHarness project.

## The Prompt

```bash
Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.
```
## This `cursor/grok4.6-high` branch

This branch is for the `cursor/grok4.6-high` model's response to the prompt.

## Environment

- Xcode 26.6
- Swift 6
- Vanilla Xcode project branched from 'vanilla' - the starting point.
- Cursor AI Agent running the prompt against the `cursor/grok4.6-high` model. Agent mode only, no plan mode used.
- Cursor had the following skills enabled:
  - Swift Concurrency Expert
  - SwiftUI-pro
  - Swiftui-view-refactor
  - xcodebuildingmcp-cli
  - ios-unit-test-skill