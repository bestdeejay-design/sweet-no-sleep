# Media pack compare — 2026-10-06 … 07

The side-by-side that decided the release media pack (issue #5). Two arena
branches each proposed a full set of media sources; this folder keeps both sets
and the pages that were used to look at them, so a later redesign can see what
was rejected and why.

| Folder | Source | Content |
| --- | --- | --- |
| `pack-cat/` | `arena/1b156f4b-sweet-no-sleep` | App icon, menu-bar awake/asleep, the three skin previews, banner, Open Graph card |
| `pack-leaf/` | `arena/c37e1c27-sweet-no-sleep` | The same eight sources in the competing treatment |
| `final/` | — | PNG renders of the adopted pack, including `leaf-fill.png` |

`compare.html` shows the two candidate packs next to each other on dark cards
(the grid was designed to approximate menu-bar and dark surfaces);
`final.html` shows the adopted result. Both are self-contained, offline pages —
open them in a browser, they load the SVGs and PNGs from this folder with
relative paths, so do not split the folder up.

The three `Снимок экрана …` PNGs are the maintainer's screenshots from the
review sessions on 2026-10-06 and 2026-10-07.

## What was adopted

From `docs/MEDIA.md`, recording the issue #5 decision:

> the golden build's Kiwi cat app icon, the SF Symbol menu bar, pack-leaf skin
> previews, the pack-cat banner base with the golden cat, and the pack-leaf Open
> Graph card with a mini app icon

So the outcome was a mix rather than a straight pick of one pack.

## Status

Historical decision record, not a source of truth. The media sources that ship
live in `Resources/Art/` with their generated deliverables in
`Resources/Art/Rendered/`; `Scripts/render-media.sh` and
`Scripts/validate-media.py` work only on those. Nothing in the build reads this
folder.
