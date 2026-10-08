# AI Agent Integrations v2 — Max-Specification & Implementation Plan

A comprehensive, decision-complete specification for the agent integration features (Issue #11, RFC v2), incorporating architectural consensus from the arena consultation.

---

## 1. Swift Signatures and Component Architecture

### 1.1. Session Model (`AgentSessionState`)
In `Sources/SweetNoSleep/SweetNoSleepModel.swift`:

```swift
enum AgentStatus: String, Codable, Sendable {
    case working
    case waiting
}

struct AgentSessionState: Equatable, Sendable {
    var status: AgentStatus
    var expiry: Date
    var reason: String?
}
```

Model Properties:
- `@Published private(set) var agentSessions: [String: AgentSessionState] = [:]`
- `@Published var agentBadgeLightEnabled: Bool` (default: `true`, key: `"agent.badgeLightEnabled"`)
- `@Published var agentCooldownMinutes: Int` (default: `1`, range: `0...5`, key: `"agent.cooldownMinutes"`)
- `@Published var agentWebhookEnabled: Bool` (default: `false`, key: `"agent.webhookEnabled"`)
- `@Published var agentWebhookToken: String` (32-char hex, key: `"agent.webhookToken"`)

Computed Properties:
- `var activeAgentCount: Int { agentSessions.count }`
- `var hasWaitingAgent: Bool { agentSessions.values.contains { $0.status == .waiting } }`
- `var isAgentActive: Bool { !agentSessions.isEmpty }`
- `var agentLightState: AgentLightState`

### 1.2. Status Light on Chest Badge (`agentLight`)
In `Sources/SweetNoSleep/KiwiPetView.swift`:

```swift
enum AgentLightState: Equatable, Sendable {
    case off
    case working
    case waiting
}
```

Render Rules:
- **`off`**: Standard center kiwi seed.
- **`working`**: Center light in active skin's `palette.accent` color with a smooth glow. Under Reduce Motion: static glow (`opacity: 0.85`).
- **`waiting`**: Center light in warm warning amber (`Color(hex: 0xE5A93C)`) with an attentive pulse. Under Reduce Motion: static amber glow.

### 1.3. Unified `baseMood()` and `.waitingForApproval`
In `Sources/SweetNoSleep/SweetNoSleepModel.swift`:

```swift
func baseMood() -> KiwiMood {
    if isBreakDue { return .breakReminder }
    if hasWaitingAgent { return .waitingForApproval }
    if isKeepingAwake { return .working }
    return .idle
}
```

State Guards:
- `.waitingForApproval` suppresses playful moments (`schedulePlayfulMoment`) and strolls (`beginWandering()`).
- Transitioning to `.waitingForApproval` explicitly invalidates `playfulTimer`.
- `poke()` returns to `baseMood()`.

### 1.4. Post-Agent Grace Cooldown
When the last agent session finishes:
- Checks published `completionAction`: if `.allowNormalSleep` and `agentCooldownMinutes > 0`, starts a 1–5 min cooldown timer.
- Status message: `"Agent finished — holding awake for N min"`.
- Any incoming agent event (`start` / `heartbeat` / `waiting`) during cooldown immediately cancels the cooldown and restores active hold.

### 1.5. Localhost Webhook Server (`Network.framework`)
In `Sources/SweetNoSleep/AgentWebhookServer.swift`:
- Binds strictly to `127.0.0.1:18290` via `NWListener`.
- Single HTTP/1.1 request per connection with `Connection: close`.
- Strict `Host: 127.0.0.1:18290` / `localhost:18290` check.
- Constant-time verification of `Authorization: Bearer <token>`.
- Endpoints: `POST /agent/start`, `POST /agent/heartbeat`, `POST /agent/waiting`, `POST /agent/done`, `POST /agent/failed`.

---

## 2. MCP Server Reference (`mcp-server/server.py`)

Single self-contained Python 3.10+ file without external pip dependencies:
- Protocol: JSON-RPC 2.0 over stdio (`sys.stdin` / `sys.stdout`).
- Logging: strictly to `sys.stderr` to prevent JSON-RPC stream corruption.
- Tools:
  - `sweetnosleep_hold(reason: str, session_id: str)`
  - `sweetnosleep_waiting(reason: str, session_id: str)`
  - `sweetnosleep_release(status: "success" | "failed", session_id: str, summary: str)`
- Transport: attempts HTTP POST to `http://127.0.0.1:18290/agent/<action>` with bearer token; falls back to `open sweetnosleep://agent/<action>?session=<id>`.

---

## 3. Presets & Hooks

- `presets/claude-code.settings.json`: maps `SessionStart`/`UserPromptSubmit` to `start`/`heartbeat`, `Notification(agent_needs_input)` to `waiting`, `Stop` to `done`.
- `presets/tasks.json`: Cursor / VS Code task templates wrapping builds and test suites.
- `Scripts/install-presets.sh`: interactive preset installer.
- `Scripts/agent-event.sh`: extended with `waiting` action support.

---

## 4. Test & Verification Plan

- `Scripts/test-agent-hooks.sh`: checks `start`, `heartbeat`, `waiting`, `done`, `failed`.
- Webhook curl test suite (valid token, invalid token 401, wrong host 403, GET 405).
- macOS verification checklist in `docs/CODE_AUDIT.md`.
