# Kot-Arbuz — character artwork (source)

Watermelon-cat character art provided by the maintainer (2026-10-08) as source
material for the "bring the character to life" arena work order (see issue #14).

- `kot-arbuz.png` — 3756 × 3756 master artwork (RGBA PNG).
- `kot-arbuz.svg` — SVG wrapper (2000 × 2000 viewBox) with the raster embedded;
  contains no vector paths — treat the PNG as the master.

Provided by the maintainer for use in this project (see LICENSE).

## Artwork revisions

| Revision | Files | State |
| --- | --- | --- |
| v1 (2026-10-08) | `kot-arbuz.png`, `kot-arbuz.svg` in this folder | Historical initial drop |
| v2 (2026-10-09) | `v2/kot-arbuz-v2.png` + `v2/kot-arbuz-v2-parts.png` (and the delivered SVG wrappers) | Active master artwork and exploded part sheet |

v2 brings a re-drawn cat plus an **exploded view of the character** with head,
tail, body and the three legs as separate pieces on a plain white background
(`v2/kot-arbuz-v2-parts.png`). That is the exact layer set the pipeline cuts from
the part sheet instead of cutting algorithmically from the flat master.

## Derived assets

The playable character lives in `Resources/PetSkins/kot-arbuz/` and is derived
from the v2 master and part sheet by `Scripts/prepare-character-assets.py`:

| File | Content |
| --- | --- |
| `head.png` | Hood, ears and face (baked eyes inpainted for vector renderer). |
| `body.png` | Torso piece from the part sheet. |
| `tail.png` | The tail crescent alone, same canvas, rotated around `tailPivotX/Y`. |
| `legs-a.png` | Left outer leg (tripod pair A). |
| `legs-b.png` | Middle leg (tripod pair B). |
| `legs-c.png` | Right outer leg (tripod pair A). |
| `pet.json` | Layer anchors and motion values for the sprite renderer. |
| `skin.json` | Name, subtitle, palette, and animation profile shared by all packs. |

The previews shown in **Settings → Pet → Skin library**
(`Resources/Art/Rendered/preview-kot-arbuz.png` and its `@2x` variant) are
composed from those same layers, so the card always shows the character exactly
as it is drawn on the desktop.

Regenerate everything after a master-art change (requires Pillow and NumPy):

```bash
python3 Scripts/prepare-character-assets.py           # rewrite the derived files
python3 Scripts/prepare-character-assets.py --check   # verify the committed ones
python3 Scripts/prepare-character-assets.py --preview /tmp/layers.png
```

The layers are extracted from `Resources/Characters/kot-arbuz/v2/kot-arbuz-v2-parts.png`,
keyed on white (`min(r,g,b) >= 245`) with alpha feathering, placed at their
recovered assembled pose offsets, and resampled to the shared 1024 × 1024 canvas.
The script verifies that recomposing the layers reproduces the assembled
`kot-arbuz-v2.png` master. Print the derived anchors after changing the art and
update `pet.json` when the script reports new values.
