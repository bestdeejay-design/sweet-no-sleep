# Sweet No Sleep media kit

The SVG files in `Resources/Art/` are the editable, hand-authored sources. They use only local vector shapes, color, and text; there are no linked images, fonts, or external assets. Review the SVG source in a text editor before changing it. Keep all text in English.

## Asset catalog

| Source | Size / viewBox | Purpose | Generated output |
| --- | --- | --- | --- |
| `app-icon.svg` | 1024 × 1024 | Kiwi cat app icon: warm beige face (`#E8C48A`), leafy green eyes, kiwi-heart mark; no wordmark | `Rendered/SweetNoSleep.icns`, complete 16–1024 px iconset, `app-icon-1024.png` |
| `menubar-awake.svg` | 22 × 22 | Awake-state monochrome template icon | `menubar-awake.png` (22 px), `menubar-awake@2x.png` (44 px) |
| `menubar-asleep.svg` | 22 × 22 | Resting-state monochrome template icon | `menubar-asleep.png` (22 px), `menubar-asleep@2x.png` (44 px) |
| `preview-kiwi.svg` | 240 × 160 | Kiwi silhouette and three palette swatches | 240 × 160 px and 480 × 320 px PNGs |
| `preview-moonlight.svg` | 240 × 160 | Moonlight silhouette and three palette swatches | 240 × 160 px and 480 × 320 px PNGs |
| `preview-strawberry.svg` | 240 × 160 | Strawberry silhouette and three palette swatches | 240 × 160 px and 480 × 320 px PNGs |
| `banner.svg` | 1280 × 640 | Product/release banner used in the README | `Rendered/banner.png` (1280 × 640 px) |
| `og-image.svg` | 1200 × 630 | Social/Open Graph composition for later use | `Rendered/og-image.png` (1200 × 630 px) |

`Resources/Art/Rendered/` contains generated deliverables, not hand-edited sources. The iconset folder is kept beside the `.icns` so CI can verify every required representation. After the macOS build and bundle checks pass, the push workflow commits these generated files to this task branch so the README's PNG link resolves; it also uploads the folder as the **sweet-no-sleep-media** artifact.

## Render and validate

The rendering script uses only macOS stock tools (`sips` and `iconutil`) and is safe to rerun:

```bash
./Scripts/render-media.sh
./Scripts/check-project.sh
```

On Linux, `render-media.sh` prints a skip message and exits successfully; raster rendering is reserved for macOS CI. The portable checks still parse every SVG, verify dimensions and self-contained references, reject Cyrillic source text, and check generated PNG dimensions if CI-rendered outputs are present. The macOS check additionally rebuilds and validates the complete iconset and both 1x/2x menu-bar images.

## Design guidance

- Keep the app icon's face silhouette, beige fur, green eyes, and kiwi-heart accent. Use a high-contrast outline and avoid text or detail that disappears at 16 px.
- Menu-bar art is a **template**: use transparent backgrounds, solid black paths, rounded joins/caps, and roughly 1 px strokes in the 22 × 22 source. macOS supplies the tint. The awake and asleep states must remain distinguishable without color.
- Skin previews are 3:2, self-contained illustrations. Show the pet silhouette first and three small palette dots second; preserve comfortable inner padding and keep the silhouette recognizable at card size.
- The banner should remain legible when displayed at half size. Keep the warm paper, sage, berry, and dark-dashboard palette; do not bake release dates or temporary pricing into the artwork.
- Do not trace or embed unlicensed third-party art. Keep source dimensions, `viewBox`, and generated 1x/2x sizes in sync.

## Adding a skin or species

A **skin** changes the existing procedurally drawn Kiwi's palette and motion profile. To give a bundled skin its own Settings-card art:

1. Add `Resources/Art/preview-<id>.svg` at 240 × 160. Keep the cat silhouette consistent with the other previews and draw palette dots from that skin's `skin.json` colors.
2. Add the ID to the preview render loop in `Scripts/render-media.sh` and the dimension tables in `Scripts/validate-media.py`.
3. Confirm the Settings card resolves `preview-<id>.png` through `MediaAssets` and test the selected outline and image at normal and Retina scale on macOS.
4. Run `./Scripts/render-media.sh` and `./Scripts/check-project.sh` on macOS; include the generated outputs only from the macOS-rendered build.

User-installed skin packs still work without a preview file; Settings falls back to the pack's palette swatches. A **new species or silhouette** is a separate product-constructor change: the current `skin.json` schema only provides colors, motion values, and an effect, so add renderer support and accessibility/animation behavior before drawing a new species preview. Do not imply that a preview alone changes the in-app pet.

## App wiring

`Scripts/build-app.sh` places `SweetNoSleep.icns` in the app's Resources directory and copies rendered menu icons and skin previews into `Contents/Resources/Media`. `MediaAssets` loads the state-appropriate template image for the menu bar and the matching built-in preview for each skin card. If generated art is not available during `swift run`, the app keeps its SF Symbol and palette-swatch fallbacks.
