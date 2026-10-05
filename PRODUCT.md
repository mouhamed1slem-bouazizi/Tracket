# Tracket product brief

## Product promise

**Tracket turns “I started it” into “people can use it.”**

The first customer is a solo developer using AI coding tools who starts many projects but loses context, confidence, or momentum before deployment. Tracket is a shipping coach connected to the work itself, not another place to manually recreate a task list.

## Core loop

1. **Observe:** Read consented local and connected signals: Git activity, open milestones, test/build status, issues, and deployments.
2. **Understand:** Estimate the current stage, momentum, blockers, and smallest credible release.
3. **Order:** Put one concrete next action above everything else and maintain a short roadmap to live.
4. **Nudge:** Remind the developer when activity cools, a deadline approaches, or a blocker remains unresolved.
5. **Verify:** Detect a deployment URL and ask for real-user feedback before treating the project as complete.

The loop optimizes for deployed projects and user feedback, not time in the app, commits, or generated code.

## MVP boundary

The macOS MVP deliberately uses folder-level signals and manual refresh. It proves that developers will trust the product, return to the recommended next action, and ship more often before deeper monitoring is added.

The app currently supports:

- local project enrollment;
- Git and workspace inspection;
- launch roadmap and deadlines;
- momentum and risk signals;
- OpenAI-generated structured planning;
- local notifications;
- launch URL capture.
- a persistent menu-bar monitor that survives closing the main window;
- local workspace and Git activity history;
- non-interactive remote Git refresh and push/incoming-work detection;
- a privacy-safe Codex lifecycle hook bridge;
- a generic JSONL event inbox for Claude Code, OpenCode, and IDE adapters.

## Connector sequence

### 1. GitHub

Add OAuth and read-only access first. Pull issues, pull requests, actions, releases, default branch activity, and deployment environments. Let the user choose repositories explicitly. Write operations should be separate, narrow permissions—for example, creating approved roadmap issues.

### 2. Codex, Claude Code, and OpenCode

Use a shared local event contract rather than building three unrelated trackers. Each adapter should emit consented events such as:

```json
{
  "project_id": "...",
  "source": "codex",
  "kind": "task_completed",
  "summary": "Implemented onboarding flow",
  "occurred_at": "...",
  "evidence": { "commit": "abc123" }
}
```

Prefer official hooks, plugins, MCP servers, and session exports. Never record raw prompts or source code by default. The event must explain what signal produced each recommendation.

The macOS MVP now implements this contract locally. Codex has a guided project-hook installer. Other agents can invoke the bundled `tracket-hook` helper until dedicated installers are added.

### 3. VS Code and Cursor

Ship one compatible extension with explicit workspace enrollment. It should show the current Tracket milestone, allow “done / blocked / defer,” and report high-level events such as successful tasks, build outcomes, and selected project. Avoid keystroke tracking and screen recording.

### 4. Xcode

Begin with project detection, build/test result imports, Git state, and deep links. Add an Xcode extension only when a specific in-editor action justifies the added setup cost.

### 5. Deployment providers

Connect Vercel, Netlify, Cloudflare, Fly.io, TestFlight, and GitHub deployments. A verified public or beta URL is the main completion signal. Deployment failure should create a recovery action, not merely lower a score.

## AI responsibilities

The AI may:

- summarize project state;
- reduce scope to a credible release;
- order milestones and suggest deadlines;
- explain risks using visible evidence;
- draft a recovery plan after inactivity or failure;
- propose one optional product idea after the core release is live.

The AI should not silently edit repositories, message collaborators, change deadlines, or deploy. Those actions require a clear preview and user confirmation.

## Trust model

- Local-first project state.
- Explicit enrollment per folder and repository.
- Clear source/evidence for momentum and recommendations.
- No keystroke, screen, or raw-prompt surveillance.
- Source code excluded from cloud planning unless the user deliberately includes it.
- Read and write permissions separated for every external connector.
- Easy pause, disconnect, export, and delete controls.

## Success metrics

North-star metric: **percentage of enrolled projects that reach a verified live URL within 30 days.**

Supporting metrics:

- time from enrollment to first completed milestone;
- weekly return to the recommended next action;
- stalled projects recovered after a nudge;
- roadmap acceptance versus immediate rewrite;
- time from first deployment to first recorded user feedback;
- connector opt-in and disconnect rates.

Commit count is only a supporting signal. Rewarding more commits directly would push the wrong behavior.

## Release path

1. Validate the local macOS loop with 10–20 solo developers.
2. Add GitHub read-only sync and deployment verification.
3. Introduce the shared coding-agent event contract and one adapter.
4. Add the VS Code/Cursor companion extension.
5. Add a small backend for accounts, encrypted connector tokens, OpenAI proxying, and cross-device state.
6. Add teams only after the solo-developer completion loop is measurably useful.
