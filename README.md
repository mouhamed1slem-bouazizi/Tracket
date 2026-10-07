# Tracket

> A local-first macOS shipping companion that helps AI-assisted developers turn unfinished projects into deployed products.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Tracket watches the development signals developers already create—workspace activity, Git changes, connected coding tools, repositories, and deployments—and turns them into a focused path to launch. It keeps monitoring from the macOS menu bar after the main window closes, estimates project completion, and brings the latest progress back into one dashboard.

## Why Tracket?

Vibe coding makes it easy to start software. Shipping is still the hard part.

Tracket is designed around a simple loop:

1. **Discover** projects from local tools and connected services.
2. **Understand** progress, momentum, blockers, and launch readiness.
3. **Focus** the developer on the next credible milestone.
4. **Monitor** local work, Git activity, and deployments in the background.
5. **Ship** to a verified live URL instead of leaving another prototype unfinished.

## Highlights

- Native SwiftUI application for macOS 14 and newer.
- Persistent menu-bar companion that continues monitoring when the main window closes.
- Automatic workspace discovery for Codex, Claude Code, OpenCode, Cursor, VS Code, and Xcode.
- Browser-based connections for GitHub, Cloudflare, Vercel, and Render.
- Automatic repository and deployment-project importing—manual project entry is optional.
- Five most recently active projects in the menu bar, including their latest development tool and completion estimate.
- Git branch, commit, working-tree, ahead/behind, push, and incoming-work detection.
- “Since you were away” activity timeline.
- Roadmaps, milestones, deadlines, momentum scoring, and launch-state tracking.
- Private on-device project planning through downloadable MLX models.
- Local, cloud, and smart-hybrid AI modes with explicit cloud-fallback permission.
- OpenAI, OpenRouter, Anthropic, DeepSeek, and custom OpenAI-compatible providers.
- Project-aware AI chat with separate sessions, memory, and learned skills for every project.
- Query-ranked repository context: project map, Git state, and focused source excerpts instead of whole-repository uploads.
- Verified, resumable local-model downloads with model deletion and clean reinstallation controls.
- An isolated local-AI helper process, so a model-runtime failure cannot terminate the Tracket interface.
- Provider usage and rate-limit details when the connected service exposes them.
- Local notifications for stalled work and upcoming milestones.
- One-click reset that removes Tracket data, credentials, bookmarks, and linked accounts without deleting project folders or cloud resources.

## Connections

| Provider | Connection | Imported data |
| --- | --- | --- |
| Codex | Local adapter and lifecycle hooks | Recent projects, activity, account usage |
| Claude Code | Local adapter | Recent projects, session and token activity |
| OpenCode | Local adapter | Database worktrees and usage statistics |
| Cursor | Local adapter | Recent workspaces |
| VS Code | Local adapter | Recent workspaces |
| Xcode | Local adapter | Recent projects and workspaces |
| GitHub | GitHub CLI browser device authorization | Repositories and API allowance |
| Cloudflare | Dynamic OAuth through Cloudflare MCP | Pages projects |
| Vercel | Dynamic OAuth with PKCE | Projects and deployments |
| Render | OAuth-protected hosted MCP | Workspaces and services |

Connection credentials are obtained through browser authorization and stored in macOS Keychain. Optional AI-provider API keys entered in Settings are also stored in Keychain and are never written to project files.

## Project AI workspace

Every project has an AI conversation panel at the bottom of its detail page. The active provider is selected in **Settings → Intelligence**, and Tracket prepares focused context from the selected project before answering.

- **Local AI** keeps prompts, relevant source excerpts, and inference on the Mac.
- **Cloud Provider** uses the configured OpenAI, OpenRouter, Anthropic, DeepSeek, or compatible endpoint and respects the selected context-sharing level.
- **Smart Hybrid** prefers the installed local model and uses the cloud only when fallback is enabled.

Conversation sessions, distilled memory, and learned project skills are stored separately for each project. Starting a new session loads that project's prior memory and skills without mixing data between projects. Removing a project or resetting Tracket removes its AI workspace data.

## Local AI models

Tracket currently supports the following Apple-silicon models:

| Model | Recommended memory | Purpose |
| --- | --- | --- |
| Qwen2.5-Coder 7B Instruct (4-bit) | 16 GB or more | Default local coding assistant |
| Devstral Small 2 (4-bit) | 32 GB or more | Larger local coding and repository reasoning model |

Model installation is resumable and verifies the configuration, tokenizer, weights index, every required SafeTensors shard, and an actual runtime load before showing **Ready**. Models can be deleted at any time from Settings. The downloaded model files remain outside the application bundle in the user's Application Support data.

## Privacy model

Tracket is local-first and intentionally avoids surveillance-style tracking.

- Project folders are accessed only after user approval.
- Security-scoped bookmarks preserve approved folder access across launches.
- OAuth credentials and optional AI-provider keys are stored in Keychain.
- Local AI automatically reads only query-relevant project files and keeps them on-device. Cloud AI uses the context-sharing level selected by the user; the whole repository is never submitted.
- Project conversations, memory, and learned skills remain isolated per project in Application Support.
- Smart Hybrid never falls back to a cloud provider unless the user enables that permission.
- The Codex event bridge records lifecycle metadata such as event name, project directory, session identifier, and tool—not prompts, command bodies, tool results, or source files.
- Monitoring can be paused, connections can be removed individually, and all Tracket data can be reset from Settings.

## Requirements

- macOS 14 or newer
- Xcode with a Swift 6 toolchain
- The Xcode Metal toolchain component for packaging local MLX inference (`xcodebuild -downloadComponent MetalToolchain`)
- GitHub CLI (`gh`) for GitHub browser authentication
- Apple silicon for on-device MLX models; cloud-provider mode remains available without a local model
- At least 16 GB memory is recommended for Qwen2.5-Coder 7B; Devstral Small 2 is offered on Macs with 32 GB or more
- An API key only when Cloud Provider or Smart Hybrid cloud fallback is used

## Run locally

```bash
git clone https://github.com/mouhamed1slem-bouazizi/Tracket.git
cd Tracket
swift run Tracket
```

Launch with sample projects:

```bash
swift run Tracket --demo
```

You can also open `Package.swift` directly in Xcode.

`swift run Tracket` is convenient for UI and cloud-provider development. Use the packaging script below when testing local models because it also builds the isolated inference helper and bundles the required MLX Metal shader library.

## Build the macOS app

```bash
xcodebuild -downloadComponent MetalToolchain
sh scripts/package-app.sh
```

The script writes `dist/Tracket.app` and `dist/Tracket-macOS.zip`. It builds the main app, the local-AI helper, and the MLX Metal shader library, then uses an installed Developer ID or Apple Development certificate when available and otherwise falls back to ad-hoc signing.

For stable Keychain and folder-permission identity across builds, select a signing certificate explicitly:

```bash
TRACKET_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
sh scripts/package-app.sh
```

## Test

```bash
swift test
```

The test suite covers project discovery, local adapters, persistence reset, activity scoring, AI-provider response parsing, project-memory isolation, repository-context ranking, model-install validation, OAuth credential compatibility, GitHub device-code parsing, and menu-bar lifecycle behavior.

## Project structure

```text
Sources/Tracket/
├── App/          Application lifecycle and menu-bar setup
├── Models/       Projects, connections, usage, and activity models
├── Services/     Discovery, OAuth, MCP, Keychain, AI, Git, and monitoring
├── Store/        Application state and orchestration
└── Views/        SwiftUI dashboard, settings, project, and menu-bar views

Sources/TracketHook/   Lightweight local event bridge
Sources/TracketLocalAI/ Isolated MLX inference helper executable
Tests/TracketTests/    Unit and integration tests
Packaging/             macOS bundle metadata
scripts/               Build and packaging utilities
```

## Product direction

The long-term goal is to measure success by projects reaching a verified live URL—not by commits, generated code, or time spent inside the app. See [PRODUCT.md](PRODUCT.md) for the product loop, trust boundaries, connector strategy, and rollout plan.

## Status

Tracket is an actively developed macOS MVP. Provider APIs and local tool formats may change, so connector compatibility is verified continuously through tests and real-world use.

## License

Copyright 2026 Mohamed Islem Bouazizi.

Licensed under the [Apache License 2.0](LICENSE). You may use, modify, and distribute Tracket under the terms of that license.
