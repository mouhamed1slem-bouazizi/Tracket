# Tracket

> A local-first macOS shipping companion that helps AI-assisted developers turn unfinished projects into deployed products.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)

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
- AI-generated project plans through OpenAI's Responses API.
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

Credentials are stored in macOS Keychain. Tracket never asks users to paste provider API tokens into the app.

## Privacy model

Tracket is local-first and intentionally avoids surveillance-style tracking.

- Project folders are accessed only after user approval.
- Security-scoped bookmarks preserve approved folder access across launches.
- OAuth credentials and the optional OpenAI API key are stored in Keychain.
- AI planning sends project metadata visible in the interface, not repository source code.
- The Codex event bridge records lifecycle metadata such as event name, project directory, session identifier, and tool—not prompts, command bodies, tool results, or source files.
- Monitoring can be paused, connections can be removed individually, and all Tracket data can be reset from Settings.

## Requirements

- macOS 14 or newer
- Xcode with a Swift 6 toolchain
- GitHub CLI (`gh`) for GitHub browser authentication
- An OpenAI API key only when AI-generated roadmaps are desired

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

## Build the macOS app

```bash
sh scripts/package-app.sh
```

The packaged application is written to `dist/Tracket-macOS.zip`. The script uses an installed Developer ID or Apple Development certificate when available and otherwise falls back to ad-hoc signing.

For stable Keychain and folder-permission identity across builds, select a signing certificate explicitly:

```bash
TRACKET_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
sh scripts/package-app.sh
```

## Test

```bash
swift test
```

The test suite covers project discovery, local adapters, persistence reset, activity scoring, provider response parsing, OAuth credential compatibility, GitHub device-code parsing, and menu-bar lifecycle behavior.

## Project structure

```text
Sources/Tracket/
├── App/          Application lifecycle and menu-bar setup
├── Models/       Projects, connections, usage, and activity models
├── Services/     Discovery, OAuth, MCP, Keychain, AI, Git, and monitoring
├── Store/        Application state and orchestration
└── Views/        SwiftUI dashboard, settings, project, and menu-bar views

Sources/TracketHook/   Lightweight local event bridge
Tests/TracketTests/    Unit and integration tests
Packaging/             macOS bundle metadata
scripts/               Build and packaging utilities
```

## Product direction

The long-term goal is to measure success by projects reaching a verified live URL—not by commits, generated code, or time spent inside the app. See [PRODUCT.md](PRODUCT.md) for the product loop, trust boundaries, connector strategy, and rollout plan.

## Status

Tracket is an actively developed macOS MVP. Provider APIs and local tool formats may change, so connector compatibility is verified continuously through tests and real-world use.

## License

No open-source license has been granted yet. The source is public for demonstration and portfolio review.
