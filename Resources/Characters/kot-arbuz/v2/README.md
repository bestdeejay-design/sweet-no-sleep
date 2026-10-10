# Kot-Arbuz v2 — updated artwork (maintainer-supplied, 2026-10-09)

Second drop of the watermelon-cat artwork. The files arrived as SVG wrappers
with a single base64 PNG inside them (no vector paths), named
`Котя-арбуз-2.svg` and `Котя-арбуз-2-1.svg`. They were extracted byte-for-byte
so the PNG here is exactly the image the SVG carries:

```python
m = re.search(r'base64,([A-Za-z0-9+/=\s]+)"', svg_text)
Path(png_path).write_bytes(base64.b64decode(re.sub(r'\s+', '', m.group(1))))
```

| File | Size | Content |
| --- | --- | --- |
| `kot-arbuz-v2.png` | 3756 × 3756, 2 148 041 B, sha256 `987d1da37d93a900…` | Re-drawn assembled cat, opaque white background |
| `kot-arbuz-v2.svg` | 2 864 352 B | The wrapper as delivered |
| `kot-arbuz-v2-parts.png` | 3756 × 3756, 2 501 402 B, sha256 `3056dd4aee862e70…` | **Exploded view: the character taken apart into six pieces** |
| `kot-arbuz-v2-parts.svg` | 3 335 500 B | The wrapper as delivered |

None of these files have an alpha channel — every pixel is opaque, background
included. `Resources/PetSkins/kot-arbuz/` is still derived from the **v1**
master one directory up; swapping it over is the arena's job (see
`artifacts/2026-10-10-work-order-kot-arbuz-v2-native-animation.md`).

## `kot-arbuz-v2-parts.png` — the six pieces

Measured on the full 3756 × 3756 canvas (non-white = any channel < 245; blobs
smaller than 500 px ignored). The pieces do not overlap and are separated by
clean background.

| Piece | Bounding box (x0, y0, x1, y1) | Size | Area | Normalised (x, y, w, h) |
| --- | --- | --- | --- | --- |
| Head (ears, face, eyes, whiskers, mouth baked in) | 1304, 80, 3195, 1927 | 1892 × 1848 | 2 583 924 | 0.3472, 0.0213, 0.5037, 0.4920 |
| Body (striped torso) | 1176, 2058, 2402, 2824 | 1227 × 767 | 719 168 | 0.3131, 0.5479, 0.3267, 0.2042 |
| Tail (crescent) | 498, 1928, 1061, 2478 | 564 × 551 | 138 134 | 0.1326, 0.5133, 0.1502, 0.1467 |
| Leg — left outer | 927, 2722, 1339, 3417 | 413 × 696 | 206 897 | 0.2468, 0.7247, 0.1100, 0.1853 |
| Leg — middle | 1729, 2885, 2035, 3417 | 307 × 533 | 128 492 | 0.4603, 0.7681, 0.0817, 0.1419 |
| Leg — right outer | 2305, 2666, 2644, 3197 | 340 × 532 | 128 167 | 0.6137, 0.7098, 0.0905, 0.1416 |

The bounding boxes describe where each piece sits **in the exploded sheet**,
not where it belongs on the assembled cat. The offsets back into the assembled
pose have to be derived by matching each piece against `kot-arbuz-v2.png`.

### Separating the pieces from the white background

**Correction, 2026-10-11.** An earlier revision of this section claimed a plain
white-key (`transparent where min(r, g, b) >= 245`) was enough, because the
interior white it removes is "0.1-1.7 % of the bounding box, i.e. edge
anti-aliasing residue". That was wrong, and it cost a review round: those
interior pixels are the artwork's **light strokes** - the cream rim between rind
and face, the highlight streaks on the cheeks and rind - and keying them leaves
see-through slits that connect to the outer rim, so they read as background and
never show up in an "enclosed hole" test. Measured on the stacked character at
1024 px (transparent pixels inside the silhouette closed by 4 px): 385 px for the
v1 layers, 403 px for the PR #32 rebuild.

What works is to take the alpha from the **contour**, not from per-pixel
whiteness: build the non-white mask, close it (or otherwise seal the thin white
channels) before flood-filling the background, then fill the interior, and verify
with the closing-based slit count (gate 5 of
`Scripts/accept-kot-arbuz-v2.py`). The cleanest input would be the pieces with
**real alpha** straight from the artist - the delivered SVG wrappers carry a flat
raster with an opaque white background, so some keying is unavoidable with these
files.

## How v2 differs from v1

Both assembled masters have the **same silhouette bounding box**
(606, 728) – (2941, 2972), i.e. 2336 × 2245 px, and
`Scripts/prepare-character-assets.py` derives **identical rig anchors** from
either one (`tailPivotX 0.0995`, `characterWidth 0.9106`, `legPivotAX 0.3686`,
…) apart from the eye anchors moving in the third decimal
(`eyeLeftY 0.5105 → 0.51`, `eyeRightY 0.4366 → 0.437`,
`eyeRadiusY 0.036 → 0.0356`).

Inside that identical silhouette the artwork is genuinely different:

| Difference | Share of the bbox |
| --- | --- |
| Any channel differs by more than 8 | 26.07 % |
| more than 24 | 9.25 % |
| more than 48 | 4.03 % |
| more than 96 | 0.94 % |
| Mean absolute difference | 8.88 / 255 |

The biggest visible change is the ring between the rind and the face: v1 paints
a thick white/cream ring, v2 keeps only a thin light rim, so the pink face
reads larger. Shading and the highlight patches on the rind, legs and tail are
smoother in v2, and the whiskers are thinner. Eyes, blush and mouth are still
baked into the head, exactly as in v1 — the renderer keeps drawing its animated
vector eyes over a head layer with the baked ones removed.

## Status

Source material only. Nothing in `Resources/PetSkins/`, `Resources/Art/Rendered/`
or `Scripts/` consumes these files yet; `kot-arbuz-v2.png` was checked once
against the existing cutter (it runs, derives the anchors above, and reports
every committed derived asset as different, which is expected).
