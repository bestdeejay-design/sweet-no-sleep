# Archive: where superseded work lives

`main` is the single source of truth. Every feature, PR and arena branch has been merged
into it, or preserved as a tag and removed as a branch — the branch list on GitHub is now
just `main`:

    git ls-remote --heads origin      # refs/heads/main

## Tags

    git tag -l 'archive/*'
    git show --stat archive/arena/af1264ab-sweet-no-sleep

| Tag | What it holds |
| --- | --- |
| `archive/arena/af1264ab-sweet-no-sleep` | The v2 delivery that `main` merged: restored effect geometry, debug instruments, per-component layers, lighter hood, tail pivot fix. |
| `archive/arena/10dec114-sweet-no-sleep` | PR #34 round 1: a shipped app renders its own bundle, not a stale checkout. |
| `archive/arena/e1ef2a3a-sweet-no-sleep` | PR #32: the first v2 art switch, aura un-clipping, waiting-reason sanitizer. |
| `archive/tmp-build` | PR #9: agent integrations F0-F5. |
| `archive/feature/agent-integrations-v2`, `archive/feat/webhook-mcp` | Earlier feature branches, merged long ago. |
| `archive/arena/<hash>-sweet-no-sleep` (11 more) | Superseded arena delivery attempts. Inspect a tag's commits with `git log archive/arena/<hash>-sweet-no-sleep`. |

Release tags: `v0.1.0`, `v1.0.0`.

## Restoring a branch from a tag

    git branch restore/af1264ab archive/arena/af1264ab-sweet-no-sleep
    git push origin restore/af1264ab

## Related

* `builds/` — three relocated PR worktrees (`pr9`, `pr16`, `pr22`) kept for reference; see `builds/README.md`.
* `artifacts/` — acceptance records with gates, logs and sheets, one folder per review.
  The v2 visual fixes are in `artifacts/2026-10-11-kot-arbuz-v2-visual-fixes/`.
