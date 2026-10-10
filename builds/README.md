# build worktrees

This folder holds the historical PR checkouts of this repository. They are
**git worktrees**, not copies: every one of them shares the object database and
the refs of the main checkout one directory above, so their commits and branches
are the same commits and branches you see with `git log`/`git branch` in the
repository root.

| Folder | Branch / ref | Origin | Status |
| --- | --- | --- | --- |
| `pr9/` | `tmp-build` | Agent-integration work orders F0–F5 (issue #11) | Superseded by `main`, kept for reference; pushed as `origin/tmp-build` |
| `pr16/` | `pr-16-acceptance` | PR #16 — Kot-Arbuz sprite pack + dashboard overflow fix | Patch-equivalent work is in `main`; kept for reference |
| `pr22/` | detached HEAD `a3cd424` | PR #22 — layered sprite rig, three skins | Commit is an ancestor of `main` |

The folders are ignored by git (only this README is tracked), so nothing here
shows up in `git status`, and `swift build` in the repository root does not
touch them.

## Use them

```bash
# normal git commands work inside a worktree
git -C builds/pr16 log --oneline -5
git -C builds/pr9 status

# build or run a worktree without rebuilding the main checkout
swift build --package-path builds/pr16
```

## Remove one

A worktree is disposable once you no longer need the checkout — the branch and
its commits stay in the main repository.

```bash
git worktree remove builds/pr9          # refuses if the tree is dirty
git worktree remove --force builds/pr9  # drops the uncommitted edits too
```

Before removing a dirty worktree, the uncommitted diffs were archived in
`artifacts/2026-10-10-worktree-consolidation/`; check there first if you need
something that was never committed.

## Add a new one

```bash
git worktree add builds/<name> <branch-or-arena-ref>
```

See `docs/WORKSPACE.md` for the whole repository layout.
