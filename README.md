# Evaluation of LLM and Agent Capabilities for iOS App Development

## Purpose

This is a LLM evaluation project for testing AI models and agents against a specific prompt that wants to build a reasonably complex SwiftUI app. The goal is to see how well the model/agent can follow the prompt and build the app to the best of its ability for the purpose of comparing the different outputs.


## The Prompt

*Given this vanilla xcode project, edit the project to give me the Swift 6 strict concurrency logic for a SwiftUI app that uses a SwiftData query in the background using a MVVM architecture with modern macros like @Observable, @Model, @ModelActor. The app simply lists tasks. Use await/async style of concurrency and avoid 'sendability hell' issues.*

## Why this prompt?

This prompt is a good test of the model/agent's ability to follow a specific prompt and build a reasonably complex SwiftUI app. It is also a good test of the model/agent's ability to use modern Swift features like Swift 6 strict concurrency, SwiftData, and SwiftUI. It is a simple prompt that hides some threading complexity that is easy to miss when building the app manually. The model must use knowledge and reasoning to build the app.

## The Starting Point

The starting point is a vanilla Xcode project that is the default starting project for a SwiftUI app when one creates a new project in Xcode v26.6. It is a good starting point because it is a simple app that is easy to understand and modify. It is also a good starting point because it is a good example of a SwiftUI app that uses SwiftData.

## The Environment

- Xcode 26.6
- Branch 'vanilla' is the starting point.
- I run the prompt against the model/agent and commit the output to the branch only.
- I edit the README.md with environment specific details and setup.

## The Output Branches

- Branch 'codex/chatgpt-5.6-high' is the outputbranch for the `ChatGPT 5.6 High` model running on Codex Desktop Agent Version 26.810.52044.
- Branch 'claude/opus5-high' is the output branch for the `Claude Opus 5 High` model running on Claude Code Agent v1.3.
- Branch 'qwen/qwen3.8-27b' is the output branch for the `Qwen 3.8 27B` model running on LM Studio Bionic v1.0.7 and OpenCode v1.18.18.
- Branch 'cursor/grok4.6-high' is the output branch for the `Grok 4.6 High` model running on Cursor v3.16.17.

## Comparison of the Output Branches

