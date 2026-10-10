# Acceptance runbook — Kot-Arbuz v2 native animation (issue #29)

How to take in the arena's PR and decide whether the shipped app really has the
**new** cat. Written 2026-10-10 against `main` @ `a9caffa`; the gates live in
`Scripts/accept-kot-arbuz-v2.py`.

Everything here exists because of what the 2026-10-10 reconnaissance found:

- the v2 silhouette is identical to v1, so "the cat changed" **cannot** be seen
  from the outline — only from the art inside it (26 % of pixels differ, mostly
  the thick white ring between rind and face that v2 thins out);
- the part sheet is **rotated**, not just spread out: the legs sit at 68–79° and
  the tail at 28° relative to the assembled pose, so any bounding-box alignment
  between a sheet piece and a layer is meaningless;
- the sheet is also a **different decomposition** from the current layers, so
  the arena has to work out the mapping instead of assuming 1:1.

And one caveat, learned the hard way the same day: a "not fully opaque pixel inside
the silhouette" metric is **not** a defect detector. It counts the anti-aliased
contour fringe of every piece and the artwork's own white channels, and it flagged a
correct rebuild. To judge colour bleed, write the review sheets and look at them on
several flat backgrounds; do not gate on a transparency count.

## 1. Materialise the PR next to the main checkout

The arena will push a branch like `arena/<session>-sns`. Worktrees live in
`builds/` (see `docs/WORKSPACE.md`):

```bash
cd /Users/best/Projects/sweet-no-sleep
git fetch origin arena/<session>-sns
git worktree add builds/arena-<session> FETCH_HEAD
cd builds/arena-<session>
```

`builds/` is git-ignored, so this never disturbs `main`.

## 2. Run the exact gates

```bash
python3 Scripts/accept-kot-arbuz-v2.py --base main \
  --app "dist/Sweet No Sleep — Kiwi Cat.app" \
  --out artifacts/acceptance-kot-arbuz-v2
```

Build the bundle first if it is absent or stale (`./Scripts/build-app.sh`) —
gate 4 exists precisely to catch an app that was not rebuilt after the art
switch, and it will fail if you point it at an old bundle.

| Gate | Proves | Fails when |
| --- | --- | --- |
| 1 `prepare-character-assets.py --check` | The committed layers, previews and `pet.json` are exactly what the pipeline derives | Anyone hand-edited a derived PNG, or the wiring and the committed assets disagree |
| 2 committed assets vs `--base` | The art really changed — `--check` was not made green by leaving the v1 pack in place | 0 of 18 layer files differ |
| 3 pipeline wired to v2 | `Scripts/prepare-character-assets.py` resolves its art inside `Resources/Characters/kot-arbuz/v2/` | The script still reads `Characters/kot-arbuz/kot-arbuz.png` |
| 4 bundle freshness | The `.app` carries byte-identical layers and previews to the committed ones | Bundle absent, stale, or built from another tree |

Gate 1 passing on the v1 pack is expected and useless on its own — that is why
gate 2 and gate 3 exist. A PR that only adds art files and does not switch the
pipeline fails gate 2 **and** gate 3.

The transform table the script prints is a hint, not a verdict: the residual
mixes art revision with decomposition differences.

## 3. Eyeball the rendered sheets

The `--out` directory gets, per pack:

- `layers-<pack>.png` — the six layers on a checkerboard; look for a clean
  silhouette, no white fringe, no stray fragments, and eyes painted out of the
  head layer (they are drawn as vectors at runtime).
- `preview-<pack>-sizes-light.png` / `-dark.png` — the skin card rendered at the
  character height for 45, 132 and 170 pt panels, on light and dark backdrops.

The dark strip on **moonlight** is the halo test: white-key artifacts show up
as a bright rim. The 45 pt tile is the legibility test.

Add the animation loops (`Resources/Art/Rendered/animation-kot-arbuz.webp`) if
the PR regenerated them.

## 4. Interactive acceptance on the Mac

1. Quit any running copy, then point LaunchServices at the new build, otherwise
   `sweetnosleep://` can route to a stale copy (see the two-copy note in the
   README):

   ```bash
   LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
   "$LSREG" -u "/path/to/old/Sweet No Sleep — Kiwi Cat.app"
   "$LSREG" -f "$PWD/dist/Sweet No Sleep — Kiwi Cat.app"
   open "$PWD/dist/Sweet No Sleep — Kiwi Cat.app"
   ```

2. Check against the issue #17 list, on the **new v2 art**:
   - the face reads bigger and the rim between rind and face is a thin light
     line, not the thick white ring of v1 — this is the quickest "is it v2?" test
     by eye;
   - eyes follow the cursor into each corner, smooth, at 45 pt and 170 pt;
   - a natural blink within ~10 s, closed eyes at rest;
   - roaming shows a walk cycle with visible leg steps, no seams opening between
     legs, body and tail;
   - petting gives cheek hearts; dance gives particles; the waiting glyph and
     the agent badge still draw;
   - three skins switch cleanly, `moonlight` shows no white halo;
   - Reduce Motion gives a static pose with no particles.

## 5. Reject and send back when

- gate 2 or gate 3 fails (art not switched, or switched only in the script);
- gate 4 fails after a clean `./Scripts/build-app.sh` (means the bundle is not
  reproducible from the committed assets);
- the recomposition tolerance the PR introduces is not justified, or recomposing
  the parts does not reproduce `kot-arbuz-v2.png` within it;
- `Resources/PetSkins/**` or `Resources/Art/Rendered/**` were edited by hand —
  gate 1 already catches this;
- `./Scripts/check-project.sh` is not green.

## 6. Then

Merge only after steps 2–4 pass; the Mac checklist is the only part that cannot
be automated. If the PR changes the pipeline's tolerances or the layer mapping,
ask for the numbers in the PR description — the next acceptance has to be able
to reproduce them.
