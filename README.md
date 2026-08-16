# LLMTestHarness-TaskManager

This is a test harness for the LLMTestHarness project. It is a simple project that allows you to test the LLMTestHarness project.

## The Prompt

```
Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.
```
## This `qwen/qwen3.8-27b` branch

This branch is for the `qwen/qwen3.8-27b` model's response to the prompt.

## Environment

- Xcode 26.6
- Swift 6
- Vanilla Xcode project (see branch 'vanilla' for the starting point)
- LM Studio Bionic server with qwen/qwen3.8-27b model running on a 2021 MacBook Pro M1 Max with 64GB of RAM
- OpenCode 1.18.18 AI Agent running the prompt against the qwen/qwen3.8-27b model running on the same macbook. 