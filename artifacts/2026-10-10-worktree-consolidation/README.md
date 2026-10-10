# Worktree consolidation — 2026-10-10

The four sibling checkouts of this repository (`sweet-no-sleep-pr9`,
`-pr16`, `-pr22`, plus the retired `sweet-no-sleep-presets-local-backup`
folder) were folded into the main project. This folder keeps the evidence and
the only content that existed nowhere else.

See `docs/WORKSPACE.md` for the resulting layout and `builds/README.md` for how
to use or remove the relocated checkouts.

## What was checked before moving anything

The three PR folders were git worktrees, so their history was already in the
main repository. Each one was audited against `main` (`1a32481`) before the
move:

| Worktree | Ref | Commits vs `main` | Files that exist only there | Verdict |
| --- | --- | --- | --- | --- |
| `pr9` | `tmp-build` (`f154467`) | 6 (`git cherry` shows all six as `+`) | none (`git diff --name-status main tmp-build` has no `A` rows) | Superseded: the F0–F5 work was ported into `main` by hand (`feat/webhook-mcp`, `feature/agent-integrations-v2`). Kept as a live worktree for reference. |
| `pr16` | `pr-16-acceptance` (`2a3ab05`) | 1 | none | `git cherry main pr-16-acceptance` marks the commit `-`, i.e. patch-equivalent work is already in `main`. |
| `pr22` | detached HEAD `a3cd424` | 0 — the commit is an ancestor of `main` | none | Already merged. |

Uncommitted edits were found in three trees; all of them are archived here as
patches, whether or not `main` already contains an equivalent:

| Patch | Contents | State in `main` |
| --- | --- | --- |
| `pr9-uncommitted.patch` | `AgentWebhookServer.swift` lifecycle hardening (synchronous `stop()`, `EADDRINUSE` bind retries, no zombie listener), a "Copy" button for the hook usage text in Settings, `.fixedSize()` on the dashboard | Same fixes exist in `main` with a different implementation (`AgentWebhookServer` has `wantsRunning`/`bindRetries`; the dashboard reserves a fixed 700 pt height). |
| `pr16-uncommitted.patch` | `Resources/Art/Rendered/og-image.png` | The working file is byte-identical to `main`'s committed render; the worktree just carried a stale index entry. |
| `pr22-uncommitted.patch` | `Resources/Art/Rendered/og-image.png` | Same as above. |

Also archived: `worktree-list-before.txt` and `branches-before.txt` (the ref
layout before the move), and `presets-local-backup-2026-10-08.tar.gz` (the
retired folder, whose unique files were folded into `presets/` — see
`presets/README.md` and `presets/repo-scoped/README.md`).

## What changed in the repository

- `git worktree move` relocated the three checkouts to `builds/pr9`,
  `builds/pr16`, `builds/pr22`; `.gitignore` now ignores `/builds/*` except
  `builds/README.md`.
- Stale `.build` caches in those worktrees (~640 MB) were deleted; they are
  regenerable per checkout.
- `presets/` gained the previously uncommitted aider presets
  (`.aider.conf.yml`, `aider-agent-wrapper.sh`, `aider-preset.md`), the
  `claude-code-hook.sh` dispatcher, a `README.md`, and the non-shipped
  `repo-scoped/` Claude Code variant. `presets/tasks.json` now wraps
  `swift build` / `swift test` instead of the template's `npm` commands.
- `Scripts/build-app.sh` also seeds `Localizable.xcstrings` (and the compiled
  tables) into `<bundle>/Contents/Resources`, the resource path that current
  SwiftPM macOS bundles use; without it `Bundle.module` could not see the
  catalog and the localization runtime check failed.
- `docs/WORKSPACE.md` documents the layout.

Nothing was deleted from the repository history: every branch that the audited
worktrees pointed at (`tmp-build`, `pr-16-acceptance`, `a3cd424`) still exists
in the main repository, and `origin/tmp-build` keeps the pushed copy.
