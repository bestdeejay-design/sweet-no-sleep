# Workspace layout and build checkouts

Maintainer-facing map of this repository's working directories: what is tracked,
what is generated, and where the historical PR checkouts live. Companion to
`docs/ARCHITECTURE.md` (what the app does) and `docs/MEDIA.md` (how the art is
produced).

## One repository, four checkouts

`/Users/best/Projects/sweet-no-sleep` is the main checkout. The PR folders that
used to sit next to it (`sweet-no-sleep-pr9`, `-pr16`, `-pr22`) were never
copies — they were **git worktrees** of the same repository, so their commits,
branches and objects always lived here. They are now relocated inside the
project:

| Path | Ref | What it was |
| --- | --- | --- |
| `builds/pr9/` | `tmp-build` | Agent integrations F0–F5 (issue #11). Superseded by `main`; pushed as `origin/tmp-build`. |
| `builds/pr16/` | `pr-16-acceptance` | PR #16: Kot-Arbuz sprite pack + dashboard overflow fix. Patch-equivalent work is in `main`. |
| `builds/pr22/` | detached HEAD `a3cd424` | PR #22: layered sprite rig and the three Kot-Arbuz skins. The commit is an ancestor of `main`. |

Everything in `builds/` is ignored by git except `builds/README.md`. The move
was done with `git worktree move`, so the worktrees stay fully functional:

```bash
git worktree list                 # all four checkouts and their refs
git -C builds/pr16 status         # git works normally inside a worktree
swift build --package-path builds/pr9
```

Removing a worktree never deletes its commits — they belong to the main
checkout. Use `git worktree remove builds/pr16` (add `--force` only when you
accept losing that tree's uncommitted edits).

The uncommitted edits that the old folders carried when they were folded in are
archived as patches in `artifacts/2026-10-10-worktree-consolidation/`, together
with a tarball of the retired `sweet-no-sleep-presets-local-backup` folder.

## What is tracked, what is generated

| Path | Tracked | Notes |
| --- | --- | --- |
| `Sources/`, `Tests/`, `Package.swift` | yes | the app |
| `Scripts/` | yes | build, checks, media and character pipelines |
| `Resources/PetSkins/` | yes | derived sprite packs (layers, `pet.json`, `skin.json`) |
| `Resources/Characters/` | yes | master character artwork, the input of the pipeline |
| `Resources/Art/` | yes | hand-authored SVG sources and generated `Rendered/` deliverables |
| `presets/` | yes | hook presets; `repo-scoped/` holds the non-shipped Claude variant |
| `docs/`, `artifacts/` | yes | architecture, orders, audit and acceptance records |
| `.build/`, `builds/*/.build/` | no | SwiftPM caches; always regenerable, safe to delete |
| `dist/` | no | assembled `Sweet No Sleep — Kiwi Cat.app` from `Scripts/build-app.sh` |
| `builds/pr9|pr16|pr22/` | no | relocated PR worktrees (only `builds/README.md` is tracked) |

## Rebuild from scratch

Deleting the caches is the supported way to recover from a confusing build
state, and it is required after a SwiftPM resource-layout change:

```bash
rm -rf .build
./Scripts/build-app.sh        # release build + render media + assemble dist/*.app
./Scripts/check-project.sh    # portable checks, then a debug build
```

`check-project.sh` runs the localization runtime verification against the
assembled app, so run `build-app.sh` first (or accept the skip message on a
fresh tree).

## Character pipeline

`Resources/Characters/kot-arbuz/` holds the master artwork; the playable layers
in `Resources/PetSkins/kot-arbuz/` are derived from it:

```bash
python3 Scripts/prepare-character-assets.py           # rewrite derived layers
python3 Scripts/prepare-character-assets.py --check   # verify the committed ones
python3 Scripts/render-character-animations.py        # headless 15 s loops
```

Never edit the derived PNGs by hand — change the master (or the pipeline) and
regenerate, or `check-project.sh` will fail.

### Accepting a character-art change

`Scripts/accept-kot-arbuz-v2.py` is the maintainer's acceptance helper for the
v2 rebuild (issue #29): four exact gates (pipeline `--check`, derived assets
changed against a base revision, the script wired to the v2 sources, and — with
`--app` — the assembled bundle carrying byte-identical assets), plus visual
sheets of the layers and of each preview at the on-screen character sizes.
Anything heuristic it prints is labelled as such and never gates. The procedure
around it is in `artifacts/2026-10-10-acceptance-kot-arbuz-v2.md`.

## Adding another checkout

```bash
git worktree add builds/<name> <branch-or-arena-ref>
```

Keep arena builds inside `builds/` so a single `git status` in the root stays
readable, and so `swift build` keeps writing to that checkout's own `.build`.
