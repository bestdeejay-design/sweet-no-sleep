# Kot-Arbuz — character artwork (source)

Watermelon-cat character art provided by the maintainer (2026-10-08) as source
material for the "bring the character to life" arena work order (see issue #14).

- `kot-arbuz.png` — 3756 × 3756 master artwork (RGBA PNG).
- `kot-arbuz.svg` — SVG wrapper (2000 × 2000 viewBox) with the raster embedded;
  contains no vector paths — treat the PNG as the master.

Provided by the maintainer for use in this project (see LICENSE).

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
