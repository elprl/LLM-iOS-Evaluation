# LLMTestHarness-TaskManager

This is a test harness for the LLMTestHarness project. It is a simple project that allows you to test the LLMTestHarness project.

## The Prompt

```bash
Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.
```
## This `claude/opus5-high` branch

This branch is for the `claude/opus5-high` model's response to the prompt.

## Environment

- Xcode 26.6
- Swift 6
- Vanilla Xcode project branched from 'vanilla' - the starting point.
- Claude Code Agent v1.3 running the prompt against the `Opus 5 High` model. Auto mode only, no plan mode used.
- Skills enabled:
  - Swift Concurrency Expert
  - SwiftUI-pro
  - Swiftui-view-refactor
  - xcodebuildingmcp-cli
  - ios-unit-test-skill

## The Output Branches

In order not to contaminate the results of subsequent model/agent's outputs, I do not add folders of the outputs. Instead, I commit the output to a new branch for each model/agent.

- Branch `codex/chatgpt5.6-sol-high` is the outputbranch for the `ChatGPT 5.6 High` model running on Codex Desktop Agent Version 26.810.52044.
- Branch `claude/opus5-high` is the output branch for the `Claude Opus 5 High` model running on Claude Code Agent v1.3.
- Branch `qwen/qwen3.8-27b` is the output branch for the `Qwen 3.8 27B` model running on LM Studio Bionic v1.0.7 and OpenCode v1.18.18.
- Branch `cursor/grok4.6-high` is the output branch for the `Grok 4.6 High` model running on Cursor v3.16.17.
- Branch `google/gemini-3.7-flash-high` is the output branch for the `Gemini 3.7 Flash High` model running on Antigravity v2.9.1.

## This branch's Solution Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the details of this branch's solution architecture.