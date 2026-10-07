# Media catalog

Every image in this project is authored as SVG in `Resources/Art` and rendered by
`Scripts/render-media.sh` into `Resources/Media`. The app, the README, and the
release bundle all read the rendered files; the SVG sources are the only files a
designer edits.

## Sources and outputs

| Source (`Resources/Art`) | Output (`Resources/Media`) | Size | Used by |
| --- | --- | --- | --- |
| `app-icon.svg` | `SweetNoSleep.icns` | 16, 32, 64, 128, 256, 512, 1024 px | `CFBundleIconFile` in the app bundle, Dock and Finder |
| `menubar-awake.svg` | `menubar-awake.png`, `menubar-awake@2x.png` | 22x22 pt, 44x44 px | Menu bar status item while a session keeps the Mac awake |
| `menubar-asleep.svg` | `menubar-asleep.png`, `menubar-asleep@2x.png` | 22x22 pt, 44x44 px | Menu bar status item while the app is resting |
| `preview-kiwi.svg` | `preview-kiwi.png`, `preview-kiwi@2x.png` | 104x52 pt, 208x104 px | Settings > Pet, Kiwi skin card |
| `preview-moonlight.svg` | `preview-moonlight.png`, `preview-moonlight@2x.png` | 104x52 pt, 208x104 px | Settings > Pet, Moonlight skin card |
| `preview-strawberry.svg` | `preview-strawberry.png`, `preview-strawberry@2x.png` | 104x52 pt, 208x104 px | Settings > Pet, Strawberry skin card |
| `banner.svg` | `banner.png` | 1280x640 | README hero |
| `og-image.svg` | `og-image.png` | 1200x630 | Social and link previews |

`Resources/Art/pet-template.svg` and `docs/PET_DRAWING_GUIDE.md` are the drawing
guide for a custom character; they are not part of the rendered catalog.

## Render the catalog

```bash
./Scripts/render-media.sh   # idempotent: rewrites the same outputs from the same sources
python3 Scripts/verify-media.py
```

The script picks the first available rasterizer:

1. `rsvg-convert` (librsvg);
2. `resvg`;
3. `Scripts/svg-render.py`, which uses the Python backends `cairosvg` or `resvg-py`
   (`pip3 install --user cairosvg`);
4. `qlmanage` + `sips`, the stock macOS tools used by the release build.

The `.icns` is packed by `iconutil` on macOS and by `Scripts/icns-pack.py` (same
PNG based container, documented in Apple's container reference) everywhere else.
When no rasterizer is present the script prints a skip message and exits 0 on
purpose: a checkout without rendering tools keeps the checked-in renders instead
of failing. `Scripts/check-project.sh` then verifies sources, sizes, and `.icns`
completeness with `Scripts/verify-media.py`.

`Scripts/build-app.sh` copies `Resources/Media` into
`Contents/Resources/Media` and the icon to
`Contents/Resources/SweetNoSleep.icns`, and sets `CFBundleIconFile`. macOS CI
renders the pack with the stock tools before assembling the bundle, so the
released icon always comes from `app-icon.svg`.

## Naming convention

```text
<role>-<variant>.svg          <role>-<variant>.png      <role>-<variant>@2x.png
```

- `role`: `app-icon`, `menubar`, `preview`, `banner`, `og-image`.
- `variant`: the state (`awake`, `asleep`) or the skin id (`kiwi`, `moonlight`,
  `strawberry`).
- Retina renders always use the `@2x` suffix and exactly twice the pixel size;
  `MediaLibrary` loads `@2x` first and pins the logical size, so the art stays
  crisp. The `.icns` carries its own scale variants and needs no suffix.

## Adding art for a new species or skin

1. Copy the closest preview source, for example
   `Resources/Art/preview-kiwi.svg` to `Resources/Art/preview-ocean.svg`.
2. Replace the hex values with the palette from
   `Resources/PetSkins/ocean/skin.json`. The palette dots at the right edge
   (`fur`, `accent`, `iris`, `cheek`) must match that manifest.
3. Keep the drawing inside `translate(34 29) scale(17.2)`: one SVG unit equals
   the pet radius, exactly like `KiwiPetView.drawPet`. Face features use the
   normalized offsets from `Sources/SweetNoSleep/KiwiPetView.swift`, so the
   preview keeps matching the live pet when that geometry changes.
4. Add the skin to the preview loop in `Scripts/render-media.sh`, add the file to
   `SOURCES` and its renders to `RENDERS` in `Scripts/verify-media.py`, then run
   the script and the checker.

New geometry, new silhouettes, and non-palette changes to the character itself
are out of scope for the manifest format: see `docs/SKIN_AUTHORING.md` for what a
`skin.json` pack can and cannot express today.

A custom pack installed in `~/Library/Application Support/SweetNoSleep/PetSkins`
can ship its own preview by placing `preview.png` or `preview@2x.png` next to its
`skin.json`; `MediaLibrary.skinPreviewImage(for:)` looks there after the bundled
catalog. Packs without preview art fall back to the palette dots on the card.

## Drawing rules

- Both artwork and product copy in `Resources/Art` are English only; the
  localization check rejects Cyrillic text in `Sources`, and media should not
  introduce a second language either.
- Text in `banner.svg` and `og-image.svg` is stored as outline paths, so the art
  renders identically without an installed font. Edit the geometry with a vector
  editor or re-run the generator that produced the outlines.
- Menu bar icons are single-colour (`#000000`) template images: macOS inverts
  them for light and dark menu bars and for the selected state. Never bake in
  colour, and keep strokes at about 1 px in the rendered image.
- The app icon is drawn on Apple's icon grid: a 1024 px canvas, an 824 px
  rounded square centered with 100 px insets on every side (the icon body grows
  beyond that square and is clipped by it), and a 185.4 px corner radius.
  `app-icon.svg` keeps that grid so the icon sits correctly next to other apps in
  the Dock and in Finder.
- Palette anchors used across the pack: background `#0A0F1B`–`#1E2F4A`, Kiwi fur
  `#E8C48A` with highlight `#FFF1D6`, outline `#5D443B`, accent green `#75C56A`,
  menu bar green `#A9D8B0`. These match the values in
  `Resources/PetSkins/*/skin.json` and the menu bar gradient in
  `SweetNoSleepApp.swift`.

## Accessibility and legibility

- The app icon is checked at 16 px and 32 px: ears, eyes, and the forehead accent
  must stay readable there, because that is the Finder and Dock size.
- Skins are distinguished by silhouette plus palette, not by palette alone, so
  the cards remain readable in greyscale and for colour-blind users.
- Every image used for product function has an accessibility label in code; the
  card and menu bar labels are set in `SettingsView.swift` and
  `SweetNoSleepApp.swift`, and decorative preview art is marked as hidden.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `SKIP media render` message | No rasterizer installed; the checked-in renders in `Resources/Media` are used as is |
| `missing render` from the checker | `Scripts/render-media.sh` was not run after adding a source |
| `SweetNoSleep.icns is missing the N px element` | The icon set was packed incompletely; re-run the render script |
| Preview card shows palette dots | The skin id has no `preview-<id>.png` and no `preview.png` in the pack folder |
| Menu bar falls back to a symbol | `Resources/Media/menubar-*.png` is missing; run the render script |
