# Kot-Arbuz v2 — the three visual fixes (2026-10-11)

`main` carries the v2 artwork (issues #33, #35). After the art switch the maintainer found
three defects on the running pet. This record keeps the evidence; all three are fixed in
`main` (commits `658b2a9`, `6331d84`).

## 1. Stray fragments beside the legs

The part boxes overlap — `body` ∩ `legs-a` 164 x 103 px, `body` ∩ `legs-c` 98 x 159 px — so
cropping a piece by its rectangle dragged a neighbour's corner into the layer: two detached
fragments of 754 px and 423 px (the tops of the outer legs) plus a 20 px one. On screen they
were two small green triangles beside the legs.

Fixed by keeping only the components that belong to the piece.

| | before | after |
| --- | --- | --- |
| assembled character | 4 blobs, **1197 px stranded** | 1 blob, **0 px stranded** |

Evidence: `fragments-before-after.png`. Mechanical gate: gate 5 of
`Scripts/accept-kot-arbuz-v2.py` (tolerance 32 px; v1 has 13 px of antialiasing specks).

## 2. The hood rim read washed out

The contour blur feathered the whole piece, leaving 0.92 % of the head layer below alpha 255.
The interior is hard 255 now and the feather lives on the outermost pixel only. The rim was
also drawn in a light green that the hue-band recolour treated as ordinary green, so it is
lightened in the part sheet before the packs are derived — 36 252 px in the head layer, +37
brightness on average — and all three themes inherit it.

Evidence: `hood-before-after.png` (base), `hood-compare.png` (all three themes).

## 3. The tail flew off the hip

The rotation pivot in `pet.json` sat 178 px from where the tail meets the body — pivot
(102,673) against a joint at (271,727) — so the base swept a ~46 px arc at a 15 degree swing
instead of staying in the hip. `tail_region()` derives the pivot from the algorithmic cut,
which no longer matches a tail taken from the part sheet.

The pivot now comes from the layers: the closest pair of tail and body pixels, pushed a third
of the way into the body — (275,728). The base moves about 1 px per 15 degrees.

Evidence: `tail-joint.png` (before: the pivot and the joint marked), `tail-fixed.png` (after:
rest, -15 and +15 degrees).

## Art and size comparisons

`compare-artwork-v1-v2.png`, `compare-sizes-v1-v2.png`, `compare-aura-v1-v2.png`,
`moods-v1-vs-v2.png`. Gate runs, logs and layer sheets are in
`artifacts/2026-10-11-issue35-acceptance/`.
