# Kot-Arbuz media pack — handover for the dajet.ru portfolio page

Work order: [sweet-no-sleep issue #18](https://github.com/bestdeejay-design/sweet-no-sleep/issues/18).
The portfolio page itself is the maintainer's draft (`ksu` branch `maintainer/kot-arbuz-draft`); this pack
contains **only the media files** it references, rebuilt from sources already committed in this repository.
Nothing here touches `ksu`. Bilingual page copy is approved in issue #18 and already lives in the draft —
this pack does not restate or retranslate it.

## Files

| File | Pixels | Weight | Cap | Source in this repo | Target path in `ksu` |
| --- | --- | --- | --- | --- | --- |
| `kot-arbuz.jpg` | 2000 × 2000 | 149 KB | 200 KB | `Resources/Characters/kot-arbuz/kot-arbuz.png` (3756², opaque white backdrop), flattened to white, LANCZOS downscale | `portfolio/characters/kot-arbuz/kot-arbuz.jpg` (works-grid cover + "Final character" gallery) |
| `skin-card.jpg` | 1200 × 800 | 66 KB | 300 KB | `Resources/PetSkins/kot-arbuz/{body,tail}.png` sprite layers, composed like `preview-kot-arbuz@2x.png` at scale 5 (sprite drawn at 752 px — downscale only) | `portfolio/characters/kot-arbuz/skin-card.jpg` ("Skin card" gallery; overlay content is ~1120 px wide) |
| `og-16.jpg` | 1200 × 630 | 49 KB | 100 KB | the same transparent sprite layers — **never the master PNG**, whose white backdrop would paint a white card on the dark page; silhouette-cropped, 520 px tall, centred, soft glow in `#7FAF5E` / `#FD5D5D` | `og-16.jpg` at the site root (og meta of `project-16/index.html`) |
| `app-states.jpg` | 2200 × 443 | 103 KB | 300 KB | `artifacts/2026-10-08-pr16-acceptance-evidence.png` (idle / 2 agents working / waiting bubble / after done / 45 pt minimum) | `portfolio/characters/kot-arbuz/app-states.jpg` ("Alive in the app" gallery) |

All four: JPEG, quality 85, progressive, optimized. Rebuild with `python3 handover/media/build_media.py`
(needs Pillow + NumPy); re-check with `python3 handover/media/verify_media.py`. Both are development
helpers, not part of `Scripts/check-project.sh`; `build_media.py --check` proves the committed JPEGs
still match the repo sources.

## Integration targets (ksu, project 16 / array index 16)

1. `const projects` entry — media fields exactly:
   `cover: 'portfolio/characters/kot-arbuz/kot-arbuz.jpg'`, `colors: ['#7FAF5E', '#FD5D5D']`;
   `titleEn: 'Kot-Arbuz — the watermelon cat'`, `categoryEn: 'Character'`;
   `titleRu` / `categoryRu` verbatim from issue #18 (already present in the draft). Index stays 16,
   old entries are never renumbered, and `16` leads `WORKS_ORDER`.
2. Overlay `case 16:` — three 1-column galleries in this order: **Final character** → `kot-arbuz.jpg`,
   **Alive in the app** → `app-states.jpg`, **Skin card** → `skin-card.jpg` (section keys `proj.16.*`
   are approved copy in the draft).
3. Root `og-16.jpg` — referenced by the `project-16/index.html` redirect stub (canonical
   `https://dajet.ru/project-16/`) and by the site's og-N convention; keep it at the root, not in the
   portfolio folder.
4. Copy the four JPEGs byte-for-byte; do not re-encode. The draft's older renders (480 × 320 skin card,
   white-backed og) are superseded by this pack.

## Verification (recorded at build time)

```
kot-arbuz.jpg   2000x2000  149 KB   (cap 200 KB)
skin-card.jpg   1200x800    66 KB   (cap 300 KB)
og-16.jpg       1200x630    49 KB   (cap 100 KB)
app-states.jpg  2200x443   103 KB   (cap 300 KB)
og-16.jpg corners: rgb(11, 11, 11) in all four 12 px patches, max channel 11
og-16.jpg near-white share: 0.032% (a leaked white backdrop would own tens of percent)
og-16.jpg character: bbox height 516 px (~520 target), centre (600, 314) of (600, 315)
```

`verify_media.py` re-runs every line above and exits non-zero on any drift.
