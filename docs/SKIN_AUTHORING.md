# Creating a Sweet No Sleep skin

A skin is a standalone directory containing a JSON manifest. New color palettes, breathing/tail profiles, and one of the built-in celebration effects do not require changes to app source. All current packs share one procedurally drawn cat character: custom sprites, new geometry, and different pet species are not supported by this format yet.

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
- `celebrationEffect` exactly matches a supported value.

An invalid manifest is skipped without preventing other packs from loading. Use a unique ID for each pack. A user pack with the same ID as a bundled skin intentionally overrides that skin.

## Develop packs separately from the app

A pack can live in its own repository or be distributed as a ZIP containing the skin directory. The app loads packs from `~/Library/Application Support/SweetNoSleep/PetSkins` and does not need the author's source code. Include attribution and licensing details for any external artwork added by future formats.

The current manifest controls palette, basic motion parameters, and one built-in effect. It cannot execute scripts, load code, or define arbitrary animations; this is intentional for safety and predictable performance.
