# Arena Technical Consultation: Agent Integrations v2

Review and decisions for the implementation plan in [Issue #11](https://github.com/bestdeejay-design/sweet-no-sleep/issues/11) and `docs/AGENT_INTEGRATIONS_PLAN.md`.

---

## 1. Architectural Decisions on the 6 Open Questions

### Question 1: Default Indicator Color (Chest Badge Light)
- **Decision:** Two-tier color mapping:
  - **`working` state (active agent lease):** Derived dynamically from `palette.accent` of the active skin (green for Kiwi, teal for Moonlight, coral for Strawberry) to maintain visual harmony.
  - **`waiting` state (waiting for user input):** Fixed warm amber/orange (`Color(hex: 0xE5A93C)` / macOS Warning Orange), identical across all skins for unambiguous visual alerting.
  - **Settings > Agent:** Checkbox to enable/disable badge light, with an *Auto (Skin Palette)* default and manual override option.

### Question 2: Priority Across Multiple Concurrent Sessions
- **Decision: `waiting` takes precedence.**
  - If multiple agent sessions run concurrently and at least one enters `waiting`, Kiwi switches to `waitingForApproval` posture, the indicator turns amber, and the informational approval bubble is displayed.
  - The underlying system power assertion remains active as long as any lease is valid.
  - Once the waiting session completes or resumes work, status automatically reverts to `working` (if other sessions remain active) or `idle`.

### Question 3: Playful Moments & Strolls Suppression During `waiting`
- **Decision:**
  - In `SweetNoSleepModel.swift`, the existing guards in `schedulePlayfulMoment` and `beginWandering()` (`mood == .working || mood == .idle`) will naturally block playful animations when `mood == .waitingForApproval`.
  - When transitioning into `.waitingForApproval`, explicitly invalidate `playfulTimer?.invalidate(); playfulTimer = nil` (identical to `breakReminder` behavior) so pending background triggers do not fire while input is requested.

### Question 4: Reduce Motion Support
- **Decision:** Full compliance with Apple HIG and existing codebase conventions:
  - Indicator light: static steady glow with constant opacity (`opacity: 0.85`, without `sin(time)` pulse).
  - Raised paw: statically positioned in raised pose without waving cycle (`sin(time * 3)`).
  - `?` glyph: rendered statically above head without vertical hover drift.

### Question 5: Localhost Webhook Token Storage
- **Decision: `UserDefaults` is the correct and sufficient choice.**
  - The webhook listens strictly on loopback `127.0.0.1:18290`. The bearer token is a capability token to prevent unwanted requests from local web browsers (CORS / DNS rebinding / port scanning protection).
  - Using `UserDefaults.standard` avoids intrusive Keychain authorization dialogs and requires no extra entitlements.

### Question 6: MCP Server Architecture & Distribution
- **Decision: Hybrid approach (`mcp-server/` with stdlib fallback).**
  - Package `mcp-server/` as a clean uv project (`pyproject.toml` with `mcp>=1.0.0`) for standard Claude Desktop / Cursor integration via `uv run server.py`.
  - Inside `server.py`, provide a standalone stdlib fallback using `urllib.request` to forward JSON-RPC tool calls to `127.0.0.1:18290` if the `mcp` library is not installed in the environment.

---

## 2. Implementation Guidelines for Swift Components

1. **`Network.framework` for Webhook Listener:**
   - Use `NWListener(using: .tcp, on: 18290)` configured with `NWParameters.LocalEndpoint = .hostPort(host: "127.0.0.1", port: 18290)`.
   - Small, zero-dependency HTTP/1.1 request parser on `queue: .main` verifying `Authorization: Bearer <token>` and parsing JSON payloads.
2. **Vector-Only Glyphs:**
   - Draw the `?` glyph procedurally via `Path` (arc + dot) inside `KiwiPetView.swift` to ensure crisp rendering at all sizes from 45 pt to 170 pt without font-metric dependencies.
3. **Thread Safety:**
   - Ensure all `NWListener` callbacks hop explicitly onto `@MainActor` before calling model methods.
