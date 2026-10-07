# AI Agent Integrations & Roadmap

A technical guide and specification for integrating coding agents (Claude Code, Cursor, Aider, Codex, OpenHands, custom scripts) with Sweet No Sleep.

---

## 1. Why traditional sleep prevention fails for AI agents

Most macOS utilities in [`sleep-prevention`](https://github.com/topics/sleep-prevention) (Amphetamine, Caffeine, KeepingYouAwake, Lungo, etc.) rely on:
- **Fixed timers:** e.g., "Keep awake for 2 hours". (Prone to underestimating long runs or keeping the Mac awake indefinitely when finished early).
- **Process/window triggers:** e.g., "Keep awake while VS Code or Terminal is open". (Ineffective because IDEs and terminals remain open all day, long after an agent finishes).

Sweet No Sleep solves this by treating agent activity as **stateful leases with heartbeat and TTL**.

---

## 2. Current capabilities in Sweet No Sleep

1. **Stateful Agent Bridge (`sweetnosleep://agent/...`):**
   - Explicit lifecycle events: `start`, `heartbeat`, `done`, `failed`.
   - **Lease / Heartbeat model:** 180-second TTL renewed by minute-interval heartbeats. If an agent crashes or hangs, the assertion automatically expires after 3 minutes.
   - **Multi-tenant concurrency:** Supports multiple simultaneous agent tasks (`activeAgentCount`); sleep protection remains active until all leases expire or complete.
2. **Transparent CLI wrapper (`Scripts/agent-session.sh`):**
   - Wraps any long-running command with automatic background heartbeats and exit status trapping:
     ```bash
     ./Scripts/agent-session.sh task-1 -- claude
     ```
3. **Fail-Safe Power Engine (P0–P2):**
   - 120-second self-expiring IOKit assertions (`kIOPMAssertionTimeoutActionRelease`).
   - Battery safety floor (pauses when battery drops $\le 20\%$).
   - Continuous uptime cap (monotonic clock protection).
   - Live hold diagnostics in the panel and Settings.

---

## 3. High-impact improvements for agent workflows

### 1. "Waiting for Approval" State (`waiting_for_approval`)
- **Use case:** Agents frequently pause during long workflows to request human approval (`y/n`, diff review, command confirmation). Active computation stops, but the workflow is not finished.
- **Specification:**
  - Add event: `sweetnosleep://agent/waiting?session=<id>`.
  - **Pet Reaction:** Kiwi enters an attentive/curious expression (e.g. raised paw, gentle sparkle) and posts a notification: *"Agent is waiting for your approval"*.
  - When the user confirms and the agent resumes, subsequent heartbeats return Kiwi to the working state.

### 2. Model Context Protocol (MCP) Server
- **Use case:** Native agent tool-calling for Claude Code, Cursor, and MCP-compatible clients without needing external shell wrappers.
- **Tools:**
  - `sweetnosleep_hold(reason: string, ttl_seconds?: number)`: Acquires or renews an awake hold for a planned batch of actions.
  - `sweetnosleep_release(status: "success" | "failed", summary?: string)`: Releases the hold and reports final outcome.

### 3. Local HTTP Webhook (`127.0.0.1:18290`)
- **Use case:** Shell URL schemes (`open sweetnosleep://...`) can be awkward inside sandboxed Node.js, Python runners, or Docker containers.
- **Specification:**
  - Lightweight localhost-only HTTP listener (`127.0.0.1:18290`):
    ```bash
    curl -X POST http://127.0.0.1:18290/agent/start -d '{"session": "task-1"}'
    curl -X POST http://127.0.0.1:18290/agent/done  -d '{"session": "task-1"}'
    ```

### 4. Post-Task Grace Period (Cooldown)
- **Use case:** Prevent immediate system sleep after late-night agent tasks, giving background disk flushes, CI triggers, and Slack/Telegram webhook notifications time to complete.
- **Specification:**
  - Configurable cooldown (1–5 minutes) in resting mode before releasing IOPM assertions.

### 5. Out-of-the-box Tooling Presets
- Pre-made configurations and aliases:
  - **Claude Code:** Hook into `settings.json` lifecycle events (`preToolUse` / `postToolUse`).
  - **Aider:** Alias: `alias aider='./Scripts/agent-session.sh aider -- aider'`.
  - **VS Code / Cursor Tasks:** Standard `tasks.json` template wrapping builds and test suites.
