# Creating a Sweet No Sleep skin

A pack is a standalone directory containing a JSON manifest. Format 1 changes color palettes, breathing/tail profiles, and one of the built-in celebration effects for the procedurally drawn cat. Format 2 additionally draws a **character** from its own layer images (`pet.json` + PNGs), which is how the bundled **Kot-Arbuz** watermelon cat ships.

Both formats obey the same rules: no new runtime dependencies, no scripts, no downloaded assets, and English-only text.

## Install a skin

1. In Sweet No Sleep, open **Settings → Pet → Open skins folder**.
2. Create a directory for the pack, for example `ocean`.
3. Put a file named `skin.json` inside it.
4. Click **Refresh list** and select the new skin card.

User packs are stored at:

```text
~/Library/Application Support/SweetNoSleep/PetSkins/<pack-folder>/skin.json
```

For example:

```text
~/Library/Application Support/SweetNoSleep/PetSkins/ocean/skin.json
```

The app reads manifests at launch and when **Refresh list** is clicked; a restart is not required. Bundled packs are in `Resources/PetSkins/` and are copied into the `.app` by `Scripts/build-app.sh`.

## `skin.json` format

Copy this template and change the values:

```json
{
  "format": 1,
  "id": "ocean",
  "name": "Ocean",
  "subtitle": "Calm shades of the sea",
  "colors": {
    "fur": "#80B8C9",
    "furLight": "#DDF4F2",
    "outline": "#294C5C",
    "innerEar": "#E8A1A0",
    "iris": "#34788B",
    "accent": "#54B9A2",
    "cheek": "#E99191"
  },
  "animation": {
    "breathingFrequency": 2.0,
    "breathingAmplitude": 0.016,
    "tailFrequency": 2.8,
    "tailAmplitude": 0.12,
    "celebrationEffect": "starburst"
  }
}
```

### Fields

| Field | Purpose | Constraints |
| --- | --- | --- |
| `format` | Pack format | `1` (palette pack, default) or `2` (character pack) |
| `id` | Stable pack identifier | 1–48 ASCII letters, digits, `-`, or `_` |
| `name` | Name shown in Settings | Must not be empty |
| `subtitle` | Short description | Any string |
| `colors.fur` | Main fur color | Hex `#RRGGBB` |
| `colors.furLight` | Light fur area | Hex `#RRGGBB` |
| `colors.outline` | Outline and face details | Hex `#RRGGBB` |
| `colors.innerEar` | Inner ears and nose | Hex `#RRGGBB` |
| `colors.iris` | Iris color | Hex `#RRGGBB` |
| `colors.accent` | Leaves, badge, and glow | Hex `#RRGGBB` |
| `colors.cheek` | Cheeks and hearts | Hex `#RRGGBB` |
| `animation.breathingFrequency` | Breathing speed, radians per second | Number `0.2…8` |
| `animation.breathingAmplitude` | Breathing strength relative to pet size | Number `0…0.08` |
| `animation.tailFrequency` | Tail speed, radians per second | Number `0.2…10` |
| `animation.tailAmplitude` | Tail range relative to pet size | Number `0…0.35` |
| `animation.celebrationEffect` | Particles during happy moments | `leaves`, `moonDust`, `berryHearts`, or `starburst` |

JSON decimals use a period. Do not add comments or trailing commas. Hex colors may include `#` or omit it; they must contain exactly six hexadecimal digits.

## Character packs (format 2)

A format 2 pack keeps every format 1 field and adds `pet.json` plus the layer
images it names. The palette still drives the glow, celebration particles,
hearts, and the badge light, so a character pack stays visually consistent with
the app theme.

```text
Resources/PetSkins/kot-arbuz/
  skin.json     # format 2, palette and motion
  pet.json      # character anchors
  body.png      # the character without the far part of the tail
  tail.png      # the tail crescent alone, same canvas
```

`pet.json` fields:

| Field | Purpose | Constraints |
| --- | --- | --- |
| `format` | Manifest format | `1` |
| `kind` | Character kind | `sprite` |
| `canvas` | Layer canvas, square | Integer 64…4096, must match both PNGs |
| `heightRatio` | How much of the layer canvas the character's height fills | Number 0.2…1.0 |
| `tailPivotX`, `tailPivotY` | Rotation point of the tail, normalized to the canvas | Number 0…1 |
| `tailSwingDegrees` | Calm idle tail amplitude (optional, default 3.5) | Number 0…30 |
| `bodyLayer`, `tailLayer` | Layer file names (optional, default `body.png` / `tail.png`) | Plain `.png` names |

Authoring rules that matter for the animation:

1. **One square canvas, identical for both layers.** Draw the tail first and the
   body over it; the two images must line up pixel-perfectly, because that is
   how the renderer restores the original artwork at rest.
2. **The body must overlap the tail root** by a few pixels, so the rotation never
   shows a seam. Aim for 1–2% of the canvas.
3. **The tail must be a separate part of the drawing**, not painted over the
   body, otherwise it cannot move.
4. **`tailPivotX/Y` is where the tail disappears behind the body**, normally the
   inner edge of its root.
5. **Keep a margin around the artwork.** The app scales the square canvas to
   about 88% of the pet box and stands its bottom edge on the resting paw line,
   so a character that touches the canvas edge would be clipped and one that
   fills the canvas would look larger than Kiwi. `prepare-character-assets.py`
   keeps roughly 6% margin on every side and records the resulting
   `heightRatio`.

What the app animates for a sprite character:

| Element | Behaviour |
| --- | --- |
| Body | Breathing (scale around the paws) plus a small working bob while agents are active |
| Tail | Sway around the pivot; lifts while an agent waits or the pet celebrates |
| Attention pose | A slight lean, an amber halo, the `?` glyph, and the y/n bubble while an agent waits |
| Badge | Agent status light plus a pip row with one dot per active session (green or amber) |
| Celebration | The pack's `celebrationEffect` around the character |

Baked-in face details do not animate: a character with drawn-on eyes cannot
blink, so keep expressions friendly and unambiguous at 45 pt. Prefer smooth,
readable silhouettes; the tail is the only part that moves independently.

### Generate the layers from a master illustration

`Scripts/prepare-character-assets.py` builds the layers, the Settings preview,
and the anchor values from a single master PNG (that is exactly how Kot-Arbuz
was produced from `Resources/Characters/kot-arbuz/kot-arbuz.png`). It needs
Pillow and NumPy and is a development helper only - the derived files are
committed, so neither the app build nor `check-project.sh` depends on it:

```bash
python3 Scripts/prepare-character-assets.py            # write layers + preview + anchors
python3 Scripts/prepare-character-assets.py --check    # verify the committed files
```

The script prints `tailPivotX` / `tailPivotY`; copy them into `pet.json`.

## Validate a pack

From the repository root, validate a pack directory or a specific manifest with the same field/range checker used for bundled packs:

```bash
python3 Scripts/validate-skins.py /path/to/ocean
# Or validate one file:
python3 Scripts/validate-skins.py /path/to/ocean/skin.json
```

If a skin does not appear after refresh, check that:

- the file is named exactly `skin.json` and is inside a pack directory;
- the JSON is valid and contains all required fields;
- the ID is safe and unique;
- colors and animation values are in range;
- `celebrationEffect` exactly matches a supported value;
- for format 2: `pet.json` exists, its ranges are valid, and both layer files
  exist as square PNGs of exactly `canvas` pixels.

`Scripts/validate-skins.py` reports all of the above, including the character
manifest, for bundled and user packs alike.

An invalid manifest is skipped without preventing other packs from loading. Use a unique ID for each pack. A user pack with the same ID as a bundled skin intentionally overrides that skin.

## Develop packs separately from the app

A pack can live in its own repository or be distributed as a ZIP containing the skin directory. The app loads packs from `~/Library/Application Support/SweetNoSleep/PetSkins` and does not need the author's source code. Include attribution and licensing details for any external artwork added by future formats.

The manifest controls the palette, basic motion parameters, one built-in effect, and (in format 2) a two-layer sprite character. It cannot execute scripts, load code, or define arbitrary animations; this is intentional for safety and predictable performance.
