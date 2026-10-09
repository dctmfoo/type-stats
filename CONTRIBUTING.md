# Contributing to TypeStats

Thanks for helping. Bug reports, small fixes and focused features are all welcome.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the shape.
- TypeStats stores counts only. A change that would store key codes, typed text, the time of a
  single press or click positions will not be accepted.

## Set up

You need macOS 14 or later, Xcode with Swift 6 or later, and Python 3 (for the checks).

```sh
swift build
swift test
sh scripts/bundle-app.sh && open .build/TypeStats.app
```

[docs/run.md](docs/run.md) explains signing, the data location and every command-line test option.
Test copies of the app should always run with `--data-dir <scratch folder> --no-tap`, so they
never touch your own counts or ask for Input Monitoring.

## Project layout

- `Sources/TypeStatsCore/`: counting, history, typing speed, pause and the SwiftData store. No
  event tap or UI, so it is unit tested.
- `Sources/TypeStats/`: the menu bar app: event tap, popup, share card and the test options.
- `Tests/TypeStatsCoreTests/`: unit tests.
- `scripts/`: building, packaging and the real-app checks, which launch the bundled app with
  simulated key presses and clicks and check what it saved and drew.
- `docs/`: the product brief, decisions, and `run.md`.
- `.po/`, `.claude/`, `AGENTS.md`: the check runner and notes for coding agents.

## Checks

Run the full check before you open a pull request:

```sh
sh .po/check.sh
```

It builds, runs the unit tests, bundles the app, runs the real-app checks listed in
`.po/check.sh` and makes sure no test copy of the app is left running. It launches the app
several times and takes a few minutes. CI runs the build, the unit tests and a launch smoke
on every pull request.

If you change behavior, add a unit test or extend a check in `scripts/` that fails without your
change, and update `docs/run.md` when a command, an option or the behavior it describes changes.

## Pull requests

- Keep each pull request to one change, with a short description of what and why.
- Match the style of the surrounding code.
- Make sure `sh .po/check.sh` passes.
