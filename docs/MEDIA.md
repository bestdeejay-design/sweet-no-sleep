# Sweet No Sleep media kit

The SVG files in `Resources/Art/` are the editable, hand-authored sources. They use only local vector shapes, color, and text; there are no linked images, fonts, or external assets. Review the SVG source in a text editor before changing it. Keep all text in English.

This layout follows the final media pack decision recorded in issue #5: the golden build's Kiwi cat app icon, the SF Symbol menu bar, pack-leaf skin previews, the pack-cat banner base with the golden cat, and the pack-leaf Open Graph card with a mini app icon.

## Asset catalog

| Source | Size / viewBox | Purpose | Generated output |
| --- | --- | --- | --- |
| `app-icon.svg` | 1024 × 1024 | Golden build's Kiwi cat icon (seated pose, leafy crown, kiwi-fruit chest badge, kiwi-heart accent); kept byte-identical to the approved build | `Rendered/SweetNoSleep.icns`, complete 16–1024 px iconset, `app-icon-1024.png` |
| `menubar-awake.svg` | 22 × 22 | Reserve cat-face silhouette, awake state, monochrome template style | `menubar-awake.png` (22 px), `menubar-awake@2x.png` (44 px) |
| `menubar-asleep.svg` | 22 × 22 | Reserve cat-face silhouette, asleep state, monochrome template style | `menubar-asleep.png` (22 px), `menubar-asleep@2x.png` (44 px) |
| `preview-kiwi.svg` | 240 × 160 | Kiwi silhouette and palette swatches (adopted pack-leaf source) | 240 × 160 px and 480 × 320 px PNGs |
| `preview-moonlight.svg` | 240 × 160 | Moonlight silhouette and palette swatches (adopted pack-leaf source) | 240 × 160 px and 480 × 320 px PNGs |
| `preview-strawberry.svg` | 240 × 160 | Strawberry silhouette and palette swatches (adopted pack-leaf source) | 240 × 160 px and 480 × 320 px PNGs |
| `preview-kot-arbuz.png` / `preview-kot-arbuz@2x.png` | 240 × 160 (and 480 × 320) | Kot-Arbuz character card, composed from the pack's own sprite layers so the card always matches the desktop pet | Generated directly by `Scripts/prepare-character-assets.py`, not by `render-media.sh` |
| `banner.svg` | 1280 × 640 | README hero: the pack-cat base layout with the golden build's cat at `translate(707.1 88.7) scale(0.49)` | `Rendered/banner.png` (1280 × 640 px) |
| `og-image.svg` | 1200 × 630 | Social/Open Graph card: the pack-leaf base with a mini app icon at `translate(67 65) scale(0.04296875)` | `Rendered/og-image.png` (1200 × 630 px) |

`Resources/Art/Rendered/` contains generated deliverables, not hand-edited sources. The iconset folder is kept beside the `.icns` so CI can verify every required representation. After the macOS build and bundle checks pass, the push workflow commits these generated files to this task branch so the README's PNG link resolves; it also uploads the folder as the **sweet-no-sleep-media** artifact.

## Render and validate

The rendering script uses only macOS stock tools (`sips` and `iconutil`) and is safe to rerun:

```bash
./Scripts/render-media.sh
./Scripts/check-project.sh
```

On Linux, `render-media.sh` prints a skip message and exits successfully; raster rendering is reserved for macOS CI. The portable checks still parse every SVG, verify dimensions and self-contained references, enforce the final decision (byte-identical app icon and reserve menu-bar renders, SF Symbol menu bar, banner and Open Graph composition anchors), reject Cyrillic source text, and check generated PNG dimensions if CI-rendered outputs are present. The macOS check additionally rebuilds and validates the complete iconset and both 1x/2x menu-bar images.

## Character previews

Preview art for the three built-in palette packs is a self-contained 3:2 SVG per
pack. A **character** pack has no SVG: its preview is composed from the same
layered sprites the pet renderer draws, which guarantees the Settings card never
drifts from the live character. Regenerate it with the pack:

```bash
python3 Scripts/prepare-character-assets.py          # layers, previews, anchors
```

The script writes `preview-kot-arbuz.png` (240 × 160) and
`preview-kot-arbuz@2x.png` (480 × 320) into `Resources/Art/Rendered/`, plus the
same pair for the recolored variant packs `kot-arbuz-moonlight` and
`kot-arbuz-strawberry`, and `Scripts/build-app.sh` copies all of them into
`Contents/Resources/Media`, so `MediaAssets.skinPreview(for:)` finds them at
runtime. Each preview composes that pack's own sprite layers (legs, tail, body,
head) and draws the rig's vector eyes at their socket anchors, so the card
shows exactly what the desktop pet draws.

## Design guidance

- **`app-icon.svg` is frozen:** it is the user-approved golden build's icon, and `Scripts/validate-media.py` pins its SHA-256. Do not restyle, re-export, or "improve" it; any change requires a new user decision in issue #5. Keep the complete iconset, macOS `iconutil` pipeline, and 16–1024 px sizes in sync with the source.
- **The menu bar is the SF Symbol `leaf.fill`**, unchanged in `SweetNoSleepApp.swift`. The bundled `menubar-awake/asleep.png` files are reserve assets the app never loads; keep their sources in the original template style (transparent background, pure-black paths, rounded joins/caps, roughly 1 px strokes at 22 × 22) and leave the rendered bytes alone unless the source itself is deliberately re-approved.
- **Skin previews are 3:2, self-contained static poses of the live Canvas-drawn Kiwi** shown on the desktop, plus the palette dots from each `skin.json`. When `KiwiPetView.drawPet`, `catHeadPath`, or the fruit badge changes, update the matching preview art without changing the live pet to match marketing.
- **The banner keeps the pack-cat composition:** dark dashboard background, wordmark, headline, feature chips, ON DUTY pill, and FOCUS IN PROGRESS box, with the golden build's cat as the mascot. The cat wrapper must stay at `translate(707.1 88.7) scale(0.49)`; that placement is verified to clear the ON DUTY pill (y 76–122) and the FOCUS IN PROGRESS box (y 560–622). Do not bake release dates or temporary pricing into the artwork.
- **The Open Graph card keeps the pack-leaf composition** and its top-left kiwi-fruit mark is replaced by a mini app icon — the rounded card plus the golden cat — at `translate(67 65) scale(0.04296875)` (exactly 44/1024 of the icon canvas). Keep the header text clear of the 67–111 px icon box.
- Keep artwork of the pet aligned with the app's actual Canvas pose wherever it appears. Do not trace or embed unlicensed third-party art. Keep source dimensions, `viewBox`, and generated 1x/2x sizes in sync.

## Adding a skin or species

A **skin** changes the existing procedurally drawn Kiwi's palette and motion profile. To give a bundled skin its own Settings-card art:

1. Add `Resources/Art/preview-<id>.svg` at 240 × 160. Keep the cat silhouette consistent with the other previews and draw palette dots from that skin's `skin.json` colors.
2. Add the ID to the preview render loop in `Scripts/render-media.sh` and the dimension tables in `Scripts/validate-media.py`.
3. Confirm the Settings card resolves `preview-<id>.png` through `MediaAssets` and test the selected outline and image at normal and Retina scale on macOS.
4. Run `./Scripts/render-media.sh` and `./Scripts/check-project.sh` on macOS; include the generated outputs only from the macOS-rendered build.

User-installed skin packs still work without a preview file; Settings falls back to the pack's palette swatches. A **new species or silhouette** is a separate product-constructor change: the current `skin.json` schema only provides colors, motion values, and an effect, so add renderer support and accessibility/animation behavior before drawing a new species preview. Do not imply that a preview alone changes the in-app pet.

## App wiring

`Scripts/build-app.sh` places `SweetNoSleep.icns` in the app's Resources directory (with `CFBundleIconFile` in `Info.plist`) and copies the rendered menu-bar reserve images and skin previews into `Contents/Resources/Media`. The menu bar itself keeps the SF Symbol and never loads the bundled PNGs. `MediaAssets` only resolves the built-in preview for each skin card; if generated art is not available during `swift run`, Settings falls back to the palette swatches.
