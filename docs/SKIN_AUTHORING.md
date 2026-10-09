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

The app reads manifests at launch, when **Refresh list** is clicked, and when the user skins folder changes (polled about every 2 seconds). A restart is not required. Bundled packs are in `Resources/PetSkins/` and are copied into the `.app` by `Scripts/build-app.sh`.

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
| `characterName` | Optional persona name the UI addresses the pet by (statuses, menus, Settings). Omit it for skins of the built-in cat — the app calls those "Kiwi"; a character pack like Kot-Arbuz sets its own name so it is never misnamed | Any string; recommended ≤ 24 chars |
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
  body.png      # torso, without tail, head and legs
  tail.png      # the tail crescent alone, same canvas
  head.png      # hood, ears and face; painted eyes inpainted out
  legs-a.png    # left outer leg (tripod pair A)
  legs-b.png    # middle leg (pair B)
  legs-c.png    # right outer leg (tripod pair A)
```

`pet.json` fields:

| Field | Purpose | Constraints |
| --- | --- | --- |
| `format` | Manifest format: `1` body + tail sprite, `2` layered rig | `1` or `2` |
| `kind` | Character kind | `sprite` |
| `canvas` | Layer canvas, square | Integer 64…4096, must match every PNG |
| `heightRatio` | How much of the layer canvas the character's height fills | Number 0.2…1.0 |
| `tailPivotX`, `tailPivotY` | Rotation point of the tail, normalized to the canvas | Number 0…1 |
| `tailSwingDegrees` | Calm idle tail amplitude (optional, default 3.5) | Number 0…30 |
| `bodyLayer`, `tailLayer` | Layer file names (optional, default `body.png` / `tail.png`) | Plain `.png` names |
| `headPivotX`, `headPivotY` | Format 2: neck pivot the head bobs and tilts around | Number 0…1 |
| `legPivotAX`, `legPivotAY` | Format 2: hip pivot of `legsALayer` | Number 0…1 |
| `legPivotBX`, `legPivotBY` | Format 2: hip pivot of `legsBLayer` | Number 0…1 |
| `eyeLeftX`, `eyeLeftY` | Format 2: socket anchor of the left vector eye | Number 0…1 |
| `eyeRightX`, `eyeRightY` | Format 2: socket anchor of the right vector eye | Number 0…1 |
| `eyeRadiusX`, `eyeRadiusY` | Format 2: half width / half height of the vector eyes | Number 0.004…0.2 |
| `headLayer`, `legsALayer`, `legsBLayer` | Format 2: layer file names (optional, default `head.png` / `legs-a.png` / `legs-b.png`) | Plain `.png` names |

Format 1 packs keep loading unchanged: the renderer draws them with the
body/tail pose and their painted face. A format 2 pack must ship every rig
layer (`head`, `legs-a`, `legs-b`) or it is refused wholesale, exactly as a pack
with a missing `body.png` is.

Authoring rules that matter for the animation:

1. **One square canvas, identical for every layer.** Draw order at rest is
   legs-a, legs-b, tail, body, head, then the vector eyes; together they must
   restore the master artwork pixel-for-pixel.
2. **Every cut keeps a static overlap band** (~2% of the canvas) inside the
   layer drawn later, so a rotating layer never shows a seam: the body keeps a
   band of tail and of hip pixels, the head keeps the neck band.
3. **The tail must be a separate part of the drawing**, not painted over the
   body, otherwise it cannot move.
4. **`tailPivotX/Y` is where the tail disappears behind the body**, normally the
   inner edge of its root.
5. **Cuts are straight rows placed where another layer covers them at rest:**
   the neck cut where the hood is as wide as the shoulders, the hip cut inside
   the torso. `headPivot*` is the centre of the neck cut; each leg layer gets
   its own `legPivot*` at its hip. Give every leg its own layer - Kot-Arbuz
   ships three - so the walk cycle can phase the outer pair against the
   middle leg.
6. **The painted eyes belong to no layer:** they are inpainted out of the head
   and replaced by vector eyes at `eyeLeft*` / `eyeRight*`. Keep seeds,
   whiskers and mouth out of the socket boxes.
7. **Keep a margin around the artwork.** The app scales the square canvas to
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
| Head (format 2) | Idle bob, a calm tilt roughly every 18 s, curious tilt, attentive raise while waiting, shake while dancing |
| Legs (format 2) | One layer per leg, each swinging around its own hip: phase-offset walk cycle while roaming or dragging, paw bounce while dancing, splay while stretching, tucked while resting |
| Eyes (format 2) | Vector eyes at the socket anchors: cursor-tracked gaze, Kiwi's 4.6 s blink, closed while resting, happy arcs while celebrating or dancing, wide while curious, waiting or dragged, half-lidded while stretching or on a break |
| Petting hearts (format 2) | Cheek-heart burst while the poke celebration plays |
| Attention pose | A slight lean, an amber halo, the `?` glyph, and the y/n bubble while an agent waits |
| Badge | Agent status light plus a pip row with one dot per active session (green or amber) |
| Celebration | The pack's `celebrationEffect` around the character |

### Mood mapping of the layered rig

All eleven `KiwiMood` cases read differently on a rigged sprite character:

| Mood | Head | Legs | Eyes | Tail and extras |
| --- | --- | --- | --- | --- |
| `idle` | slow bob, ~2° tilt every 18 s | relaxed | open, gaze + blink | calm sway |
| `working` | quicker micro-bob | relaxed | open, gaze + blink | sway x1.2, badge light |
| `celebrating` | hop + 2.4° shake | alternating bounce | happy arcs | sway x2 + lift, skin celebration, cheek hearts |
| `dancing` | 3° shake at 6.2 rad/s | paw bounce, phase-offset | happy arcs | sway x2 + lift, skin celebration |
| `stretching` | -2° tilt, lifted | splayed +-5° | half-lidded | body stretch |
| `curious` | +3° tilt with a slow wobble | relaxed | wide | calm sway, star sparkle |
| `breakReminder` | -2° tilt, lowered | relaxed | half-lidded | slow sway, halo + sparkle |
| `resting` | dropped 1%, +1.5° | tucked, -+3° | closed | sway x0.5 |
| `dragging` | 1.5° wobble at 9 rad/s | dangling swing +-7° | wide | drooped tail |
| `walking` | step bob at 8 rad/s | walk cycle +-6°, phase-offset pairs | open, gaze + blink | sway x1.4 |
| `waitingForApproval` | raised 1%, +1.5° | planted | wide | raised tail, amber halo + `?` glyph |

With Reduce Motion (or animations off) every oscillation freezes to its static
offset - the resting drop, the waiting raise, the tucked legs - and no
particles are drawn; the halo, badge light and waiting glyph stay as the
non-motion awareness cues.

Format 2 removes the old "painted face" limit: `prepare-character-assets.py`
inpaints the master's painted eyes out of the head layer and records the socket
anchors, so the renderer can draw vector eyes that blink and track the cursor.
Keep the sockets clear of whiskers, seeds and mouth, and keep expressions
readable at 45 pt.

### Bundled character skins

Kot-Arbuz ships as three packs that share one rig and one master illustration:
`kot-arbuz` (leaves), `kot-arbuz-moonlight` (moon dust stars) and
`kot-arbuz-strawberry` (berry hearts). The variants are hue-band recolors of the
same layers, written by `prepare-character-assets.py` together with their
`skin.json`, `pet.json` and Settings previews.

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

The script writes every `pet.json` (format 2) itself, plus the recolored
variant packs and all Settings previews; `--check` verifies the committed files
against a fresh derivation.

## Validate a pack

From the repository root, validate a pack directory or a specific manifest with the same field/range checker used for bundled packs:

```bash
python3 Scripts/validate-skins.py /path/to/ocean
# Or validate one file:
python3 Scripts/validate-skins.py /path/to/ocean/skin.json
```

## Format 1 → 2 recipe

Format-1 packs keep the procedural cat. To become a character pack:

1. Set `"format": 2` in `skin.json`.
2. Add `pet.json`. Format 1 of `pet.json` is `body.png` + `tail.png` (legacy pose). Format 2 of `pet.json` is the layered rig (`head.png`, `legs-a.png`, `legs-b.png`, `legs-c.png`, plus body and tail).
3. Copy `Resources/PetSkins/kot-arbuz/` as a working template; every declared layer must be a square PNG of `canvas` pixels. A format-2 pack missing any rig layer is refused wholesale.

`Scripts/validate-skins.py` prints this migration hint when a character pack fails validation.

If a skin does not appear after refresh, check that:

- the file is named exactly `skin.json` and is inside a pack directory;
- the JSON is valid and contains all required fields;
- the ID is safe and unique;
- colors and animation values are in range;
- `celebrationEffect` exactly matches a supported value;
- for format 2: `pet.json` exists, its ranges (including the rig anchors) are
  valid, and every layer file - body, tail, head, legs-a, legs-b - exists as a
  square PNG of exactly `canvas` pixels.

`Scripts/validate-skins.py` reports all of the above, including the character
manifest, for bundled and user packs alike.

An invalid manifest is skipped without preventing other packs from loading. Use a unique ID for each pack. A user pack with the same ID as a bundled skin intentionally overrides that skin.

## Develop packs separately from the app

A pack can live in its own repository or be distributed as a ZIP containing the skin directory. The app loads packs from `~/Library/Application Support/SweetNoSleep/PetSkins` and does not need the author's source code. Include attribution and licensing details for any external artwork added by future formats.

The manifest controls the palette, basic motion parameters, one built-in effect, and (in format 2) a two-layer sprite character. It cannot execute scripts, load code, or define arbitrary animations; this is intentional for safety and predictable performance.
