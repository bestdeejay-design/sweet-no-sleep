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
| v1 (2026-10-08) | `kot-arbuz.png`, `kot-arbuz.svg` in this folder | What the committed derived assets are built from |
| v2 (2026-10-09) | `v2/kot-arbuz-v2.png` + `v2/kot-arbuz-v2-parts.png` (and the delivered SVG wrappers) | Delivered, not wired into the pipeline yet |

v2 brings a re-drawn cat plus something v1 never had: an **exploded view of the
character** with head, tail, body and the three legs as separate pieces on a
plain white background. That is the exact layer set the current pipeline cuts
algorithmically out of the flat master. Swapping the pipeline over to v2 is the
subject of
`artifacts/2026-10-10-work-order-kot-arbuz-v2-native-animation.md`; the numbers
that task depends on are in `v2/README.md`.

## Derived assets

The playable character lives in `Resources/PetSkins/kot-arbuz/` and is derived
from this master by `Scripts/prepare-character-assets.py`:

| File | Content |
| --- | --- |
| `body.png` | The character without the far part of the tail. |
| `tail.png` | The tail crescent alone, same canvas, rotated around `tailPivotX/Y`. |
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

The layers are cut automatically: the backdrop is flood-filled from the border,
the white outlines are closed so the fill cannot leak into the tail, and the
tail is separated at the gap the artwork leaves between the crescent and the
body. Print the derived anchors after changing the art and update `pet.json`
when the script reports new values.
