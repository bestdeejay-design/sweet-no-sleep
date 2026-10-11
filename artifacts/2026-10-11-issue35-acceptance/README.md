# Issue #35 acceptance — Kot-Arbuz v2 layers (post-merge)

Re-run of the acceptance for the per-component layer crop (`658b2a9`) and the
tail-pivot fix (`6331d84`) on `main` @ `505193c`, base `3c8ac30`.

- `sweet-no-sleep-issue35-acceptance.html` — the record: gate numbers, CI
  links, the on-screen checklist and the reproduction commands (sheets
  embedded).
- `acceptance-run.log` — `Scripts/accept-kot-arbuz-v2.py ... → VERDICT: ACCEPT`
  (gate 5: 0 px on all three packs).
- `check-project.log` — `./Scripts/check-project.sh`, exit 0.
- `gate5-three-revisions.py` / `.log` — gate 5 across three revisions:
  v1 13 → pre-fix v2 1197 → fixed 0 px.
- `sheets/` — nine acceptance sheets (six layers per pack; size previews at
  45 / 132 / 170 pt on light and dark).

CI: [main @505193c](https://github.com/bestdeejay-design/sweet-no-sleep/actions/runs/38124842001) ·
[branch @6331d84](https://github.com/bestdeejay-design/sweet-no-sleep/actions/runs/38124840190).
