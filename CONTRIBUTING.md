# Contributing to SweetNoSleep

Thanks for your interest in SweetNoSleep, a macOS menu bar companion with the Kiwi pet.
This guide covers how to build, branch, and submit changes.

Repository: bestdeejay-design/sweet-no-sleep. Target platform: macOS 14 and later.

## Requirements

- macOS 14 or later (Apple Silicon or Intel)
- Xcode command line tools (`xcode-select --install`)
- Swift 5.9 or later (`swift --version`)

## How to Build

```sh
swift build
./Scripts/check-project.sh
```

`swift build` compiles the Swift package. `Scripts/check-project.sh` runs the
portable project checks (the same checks used in CI). Run both before opening
a pull request.

To assemble the app bundle locally:

```sh
./Scripts/build-app.sh release
```

## Branch Rules

- Never push directly to `main`. All changes go through a pull request.
- Create a feature branch from `main`: `feature/short-name` or `fix/short-name`.
- Keep branches small and focused. One branch, one purpose.
- Rebase on `main` before requesting review if your branch falls behind.
- Every pull request needs a review by the maintainer. Final acceptance on a
  real Mac (macOS 14 or later) by the maintainer is required before merge.
- CI (`.github/workflows/macos.yml`) must pass before merge.

## Pull Request Checklist

- [ ] `swift build` passes
- [ ] `./Scripts/check-project.sh` passes
- [ ] Tested on macOS 14+ (state device: Apple Silicon or Intel)
- [ ] No unrelated changes included

## English-Only Rule

All code, comments, documentation, commit messages, issues, pull requests,
and user-facing strings must be in English. Do not add non-English text.
User-facing strings shown next to the Kiwi pet must also stay in English.

## Code Style

- Follow the existing Swift style in `Sources/`.
- Keep functions small and names descriptive.
- Do not commit build artifacts (`.build/`, `dist/`).

## Reporting Issues

Use the bug report or feature request templates. Include your macOS version
and whether you run on Apple Silicon or Intel.

---

SweetNoSleep is built by Axiiom Studio (https://axiiom.ru, part of https://dajet.ru).
