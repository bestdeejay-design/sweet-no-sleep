# AI Agent Integrations v2 — Final Technical Audit & Delta Decisions

This document records the final audit decisions on the 5 implementation deltas for Issue #11 and `docs/AGENT_INTEGRATIONS_PLAN.md`.

---

## Delta 1: Diff-Scope Statement & Framework Allowlist

### 1.1. Framework Allowlist Amendment
`Network.framework` is officially amended into the Scope Guard allowlist in `docs/IMPROVEMENTS.md` (no external runtime dependencies; Apple stock frameworks only: `IOKit`, `AppKit`, `ServiceManagement`, `Foundation`, `Network`).

### 1.2. Strict File Boundaries
- **Permitted to Modify / Create:**
  - `Sources/SweetNoSleep/*.swift` (including new `AgentWebhookServer.swift`)
  - `Sources/SweetNoSleep/Localizable.xcstrings`
  - `Scripts/*.sh` (including new `install-presets.sh`)
  - `mcp-server/server.py`
  - `presets/*.json`
  - `docs/*.md`
  - `README.md`
- **MUST NOT TOUCH (Strictly Untouchable):**
  - `Resources/Art/*` (8 SVG sources, 14 rendered PNGs, iconset, `SweetNoSleep.icns`)
  - `Resources/PetSkins/*` (all `skin.json` manifests)
  - `Scripts/render-media.sh`
  - `Scripts/validate-media.py`
  - `Scripts/validate-skins.py`

---

## Delta 2: Host & Origin Security Policy for Webhook

### 2.1. Strict Host Rule
- **Rule:** Strict `Host: 127.0.0.1:18290` check ONLY.
- **Rationale:** `localhost` is explicitly rejected to eliminate DNS-rebinding vulnerabilities from malicious domains (e.g., `localhost.attacker.com` resolving to 127.0.0.1).

### 2.2. Origin Header Validation
- If the `Origin` header is present (browser-originated request):
  - Must equal `http://127.0.0.1:18290` or `null`.
  - Any external origin (e.g. `https://malicious-website.com`) returns `403 Forbidden` immediately.

### 2.3. Authentication
- Constant-time verification of `Authorization: Bearer <token>` to prevent timing attacks.

---

## Delta 3: `NWListener` Lifecycle & Error Surfacing

### 3.1. MainActor Threading
- `NWListener` runs its connection acceptance on a dedicated internal queue; all model state mutations hop explicitly to `@MainActor` via `Task { @MainActor in ... }` or the main queue.

### 3.2. Port Conflict Surfacing
- If binding port `18290` fails (e.g. port already occupied by another service or duplicate instance):
  - Sets `@Published var agentWebhookError: String? = "Port 18290 is already in use"` in `SweetNoSleepModel`.
  - Displayed in **Settings > Power (or Agent)** as a warning card with an alert icon.

### 3.3. macOS Firewall Dialog Prevention
- Binding strictly to `127.0.0.1` (`NWEndpoint.hostPort(host: "127.0.0.1", port: 18290)`) ensures macOS does not trigger the "Do you want the application to accept incoming network connections?" firewall prompt.

---

## Delta 4: Grace Cooldown Timer Cancellation Exact Boundaries

The post-agent grace cooldown timer is cancelled in exactly 4 lifecycle events:

1. **`renewAgentLease` / New Agent Event:** If a new event arrives (`start`, `heartbeat`, `waiting`) while the grace cooldown timer is ticking, the timer is cancelled immediately and the session transitions back into active lease hold.
2. **`stopKeepingAwake` / Manual Stop:** User manually clicking "End session" or toggling off awake mode cancels the grace timer immediately and completes full teardown.
3. **`powerKeeper.onFailure`:** Any kernel IOKit failure immediately aborts and clears the timer.
4. **`NSWorkspace.willSleepNotification`:** System-initiated sleep immediately cancels the grace timer and releases assertion handles so the Mac is not prevented from sleeping.

---

## Delta 5: `agentLight` Rendering & Manual Mode Decoupling

### 5.1. Model Decoupling
- `agentLightState` is driven **strictly by `agentSessions`** and the `agentBadgeLightEnabled` setting:
  - `.off` if `!agentBadgeLightEnabled` or `agentSessions.isEmpty`.
  - `.waiting` if `hasWaitingAgent` (`agentSessions.values.contains { $0.status == .waiting }`).
  - `.working` if `!agentSessions.isEmpty`.
- **Manual awake mode without active agents correctly shows `.off`**, preventing false-positive agent activity indicators.

### 5.2. View Plumbing
- Passed explicitly: `model.agentLightState` -> `KiwiPetView` -> `drawPet(..., agentLight: agentLight)` -> `drawKiwiBadge(..., agentLight: agentLight)`.

### 5.3. Animation & Reduce Motion
- 24 fps TimelineView smooth pulse during normal execution.
- Under Reduce Motion: static glow (`opacity: 0.85`), zero sine oscillation.
