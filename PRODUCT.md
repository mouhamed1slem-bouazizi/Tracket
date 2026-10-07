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

## Current macOS product

The macOS app combines local project observation, connected-service imports, background monitoring, and project-aware AI. It is designed to prove that developers will trust the product, return to the recommended next action, and ship more often before team workflows or cross-device sync are added.

The app currently supports:

- automatic project discovery from Codex, Claude Code, OpenCode, Cursor, VS Code, and Xcode;
- browser-authorized imports from GitHub, Cloudflare, Vercel, and Render;
- Git and workspace inspection, including remote push and incoming-work detection;
- launch roadmaps, deadlines, momentum, risk signals, and local notifications;
- a persistent menu-bar monitor that survives closing the main window;
- a privacy-safe lifecycle event bridge for coding agents and IDE adapters;
- local, cloud, and smart-hybrid AI planning;
- downloadable and removable MLX coding models with verified installation;
- project-aware AI conversations with separate history, memory, and learned skills;
- bounded, query-ranked repository context instead of whole-repository submission;
- launch URL capture and deployment-project discovery;
- complete local reset of projects, bookmarks, AI state, and linked accounts.

## Connector sequence

### 1. GitHub — implemented foundation

GitHub uses browser device authorization through GitHub CLI and imports repositories plus API allowance information. The next connector depth should add opt-in issues, pull requests, actions, releases, and deployment environments. Write operations should remain separate, narrow permissions—for example, creating approved roadmap issues.

### 2. Codex, Claude Code, and OpenCode — implemented foundation

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

The macOS app implements this contract locally, discovers recent projects, and imports available usage information. Codex has a guided project-hook installer. Other agents can invoke the bundled `tracket-hook` helper until dedicated installers are added.

### 3. VS Code and Cursor — discovery implemented

Tracket imports recent workspaces from both editors. A future compatible extension can show the current milestone, allow “done / blocked / defer,” and report high-level build outcomes with explicit workspace enrollment. It must avoid keystroke tracking and screen recording.

### 4. Xcode — discovery implemented

Tracket detects recent projects and combines them with Git state. Build/test result imports and deep links are the next useful additions. An Xcode extension should be added only when a specific in-editor action justifies the setup cost.

### 5. Deployment providers — imports implemented

Cloudflare, Vercel, and Render connections import deployment projects today. Netlify, Fly.io, TestFlight, and GitHub deployment environments are future candidates. A verified public or beta URL remains the main completion signal. Deployment failure should create a recovery action, not merely lower a score.

## AI responsibilities

The AI may:

- summarize project state;
- reduce scope to a credible release;
- order milestones and suggest deadlines;
- explain risks using visible evidence;
- draft a recovery plan after inactivity or failure;
- answer project-specific questions using a bounded repository map and ranked excerpts;
- preserve separate conversation history, memory, and learned skills for each project;
- propose one optional product idea after the core release is live.

The AI should not silently edit repositories, message collaborators, change deadlines, or deploy. Those actions require a clear preview and user confirmation.

## Trust model

- Local-first project state.
- Explicit enrollment per folder and repository.
- Clear source/evidence for momentum and recommendations.
- No keystroke, screen, or raw-prompt surveillance.
- Source code excluded from cloud planning unless the user deliberately includes it.
- Local inference may read query-relevant files on-device without transmitting them.
- Conversation history, memory, and learned skills are isolated per project.
- Local model downloads are verified before activation and can be deleted from Settings.
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

1. Validate the complete local macOS loop with 10–20 solo developers.
2. Harden connector compatibility and add deeper read-only GitHub/deployment evidence.
3. Add VS Code/Cursor and Xcode companion surfaces only for high-value milestone and build signals.
4. Sign, notarize, and distribute production builds with automatic updates.
5. Consider an optional backend for cross-device state without weakening local-first privacy.
6. Add teams only after the solo-developer completion loop is measurably useful.
