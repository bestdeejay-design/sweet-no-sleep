# AI Agent Integrations v2 — Autonomous Implementation Order

> **Read this document to the end. It is self-contained: every decision is frozen, every rule is final.**
> No clarification round-trips are needed. If something is ambiguous, the frozen artifacts in §2 win over any inference; if a genuine conflict remains, pick the most conservative reading, note it in the PR description, and proceed.

---

## 1. Mission

Implement the **AI Agent Integrations v2** feature set in the `sweet-no-sleep` macOS app, exactly as specified by the frozen artifacts below. You are the implementer. The maintainer (user) will hand this document to you by URL only — treat it as the complete brief.

- Repository: `bestdeejay-design/sweet-no-sleep`
- Current implementation branch (your working base): `arena/22936f10-sweet-no-sleep`
- Open PR: **#9** — add the new implementation commits to this branch/PR.
- Reference issue: **#11** — the plan and consultation live there.

## 2. Frozen Artifacts (authoritative — read all four, in order)

All files live in this branch. Read them fully before writing any code:

1. `docs/AGENT_INTEGRATIONS.md` — original roadmap (what/why).
2. `docs/AGENT_CONSULTATION.md` — arena answers to the 6 open questions (color semantics, waiting precedence, playful-guard, Reduce Motion, token storage, MCP transport) + 3 Swift guidelines.
3. `docs/AGENT_INTEGRATIONS_PLAN.md` — **the max-spec**: session model, `AgentLightState`, baseMood(), grace cooldown, webhook server, MCP server, presets, Settings UI, test plan.
4. `docs/AGENT_AUDIT.md` — **final audit of 5 deltas** (diff-scope, Host/Origin policy, NWListener lifecycle, grace-timer cancellation points, agentLight threading). Where it differs from the plan, the audit wins.
5. `docs/IMPROVEMENTS.md` — Scope Guard rules (already amended: `Network.framework` is allowed).

## 3. Scope — what to implement

Implement **F0–F5** from the plan, honoring every audit decision:

- **F0 — `agentLight` indicator**: `AgentLightState` (`off`/`working`/`waiting`) driven strictly from `agentSessions` + `agentBadgeLightEnabled` (manual awake mode with no agents ⇒ `.off`, no false positives). Threaded `model.agentLightState → KiwiPetView → drawPet → drawKiwiBadge`. 24 fps pulse `0.65 + 0.35 * sin(time * 2.8)`; static `opacity: 0.85` under Reduce Motion.
- **F1 — `waitingForApproval`**: `AgentSessionState { status working|waiting, expiry, reason? }`, `agentSessions` `@Published private(set)`, `hasWaitingAgent`, `baseMood()` helper replacing duplicated mood formulas, `poke()` returns to `baseMood()`, playful guard + timer invalidation on waiting entry, raised-paw + `?`/`!` glyph (Path only) + y/n bubble, waiting precedence over break reminders.
- **F2 — MCP server**: single stdlib-only `mcp-server/server.py` (JSON-RPC 2.0 over stdio, tools `sweetnosleep_hold`/`sweetnosleep_waiting`/`sweetnosleep_release`, session_id passed by client, log to stderr only). **No `ttl_seconds`** (it was a lie against code — `agentLeaseTimeout = 180` is the app-side truth). HTTP POST transport → webhook; fallback `open sweetnosleep://…` on connection refusal.
- **F3 — Webhook server**: `NWListener` on `127.0.0.1:18290` only (`NWEndpoint.hostPort(host: "127.0.0.1", port: 18290)` — no firewall prompt). Strict `Host: 127.0.0.1:18290` (reject `localhost` — DNS-rebinding), `Origin` if present must be `http://127.0.0.1:18290` or `null` else `403`, constant-time `Authorization: Bearer` compare, POST-only, one request per connection + `Connection: close`, body ≤ 4 KB, headers ≤ 8 KB, `100 Continue` for `Expect`, 200/400/401/403/404/405/413. All handler hops to `@MainActor` via `Task { @MainActor in … }`. Port busy ⇒ `@Published agentWebhookError` surfaced in Settings. Token in `UserDefaults.standard`, regenerate control in Settings.
- **F4 — Grace cooldown**: after last agent lease, when published `completionAction == .allowNormalSleep`, hold awake N minutes (`agentCooldownMinutes`, default 1, range 0–5, 0 = off). Cancelled at **exactly 4 points**: `renewAgentLease` (new agent event), `stopKeepingAwake`, `powerKeeper.onFailure`, `NSWorkspace.willSleepNotification`. `end()` idempotent; grace survives system sleep (willSleep releases assertions, grace timer restarts cleanly).
- **F5 — Presets**: `presets/claude-code-hooks.settings.json` (SessionStart/UserPromptSubmit → start/heartbeat; Notification(`agent_needs_input`/`permission_prompt`) → waiting; Stop/StopFailure/Notification(`agent_completed`) → done/failed), `presets/tasks.json` (Cursor/VS Code), `Scripts/install-presets.sh`, `Scripts/agent-event.sh` extended with `waiting`, `Scripts/test-agent-hooks.sh` extended (start, heartbeat, waiting, done, failed).

## 4. Hard Rules (non-negotiable)

- **English only** in code, docs, strings. Localization exclusively via `Scripts/localize.sh`; validate keys after changes.
- **No new runtime dependencies.** Frameworks allowed: `IOKit`, `AppKit`, `ServiceManagement`, `Foundation`, `Network`.
- **MUST NOT TOUCH:** `Resources/Art/*` (8 SVG, 14 PNG, iconset, `SweetNoSleep.icns`), `Resources/PetSkins/*` (`skin.json`), `Scripts/render-media.sh`, `Scripts/validate-media.py`, `Scripts/validate-skins.py`. The menu bar icon is **never** changed (sha256 `ec3b5ef42f338d5179501edebf8be993b254414c34f0115d03dd41de5eb7fda1`).
- **No `UNUserNotificationCenter`** (not in the allowlist). In-app status only.
- Do not touch `agentLeaseTimeout = 180` (SweetNoSleepModel.swift:70). No per-session TTL in the MCP server.
- Match existing codebase patterns (see `Sources/SweetNoSleep/` conventions). No `as any`/`@ts-ignore` equivalents in Swift; no empty catch blocks.
- `check-project.sh` regenerates `Resources/Art/Rendered/og-image.png` — restore it (`git checkout --`) after every run; it must never appear in your diff.

## 5. Definition of Done (all must pass before you open the PR)

1. `./Scripts/check-project.sh` exits 0.
2. Full Xcode build succeeds; unit tests pass.
3. `Scripts/test-agent-hooks.sh` passes for all five events (start, heartbeat, waiting, done, failed).
4. Webhook curl smoke suite: 200 valid bearer, 401 bad token, 403 wrong Host, 403 foreign Origin, 405 GET, 413 oversized body.
5. MCP server smoke: stdio handshake (`initialize`), `tools/list` returns the three tools, one `tools/call` round trip per tool.
6. `git diff` confirms: no touched files from §4 MUST-NOT-TOUCH list, except the og-image restore.
7. Diagnostics clean (no new warnings in changed files).

## 6. Commit & PR Protocol

- Work directly on `arena/22936f10-sweet-no-sleep` (the PR #9 branch). Commit in small logical steps with Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Push to origin. Update PR #9 with a description listing: files changed, per-feature notes, DoD results, and any conservative-reading decisions you made.
- **Never merge the PR. Never force-push.** The maintainer merges after Mac acceptance.

## 7. Final Behavior

Deliver a short completion report in the PR description: one line per feature (F0–F5) stating what was implemented and the DoD result. If you deviated anywhere, say exactly where and why. Do not ask the user anything — the order is complete.