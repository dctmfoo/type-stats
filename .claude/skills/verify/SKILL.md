---
name: verify
description: Verify a type-stats change in the real macOS app before calling it done. Runs the project checks, drives the behavior you changed in the bundled menu bar app, captures a screenshot or output, and cleans up every test copy. Use for any change under Sources/, Tests/ or scripts/, including pure UI changes.
---

# Verify type-stats (native macOS menu bar app)

A successful build, a source grep or a search for a view name is NOT verification.
Keep every fixture, data dir and screenshot under `.po/tmp/`, in a fresh folder per run.

1. Run `sh .po/check.sh`. It builds, runs the unit tests and every real-app check in
   `scripts/` (app-smoke, share, exclude, pause). Run it as one command; do not
   run the scripts alone. Report which checks ran and their result.
2. Drive the behavior you changed in the real bundle (`sh scripts/bundle-app.sh` first).
   The test seams are the table in `docs/run.md` ("Test seams"); use it, do not copy it here.
   Start with `--data-dir .po/tmp/<fresh-name> --no-tap` so nothing touches the owner's data.
3. Capture evidence and look at it. `--snapshot <png>` renders the popup without Screen
   Recording permission; `--show-window` plus `screencapture -x -l <window id>` shows
   scrolling lists, which `--snapshot` omits. Say plainly what could not be driven (the
   real event tap, menu clicks) and leave it as a limit; do not claim it.
4. If no script in `scripts/` fails when your change breaks, add one and call it from
   `.po/check.sh`. Show it fail once against a deliberately broken build.
5. Clean up. Every copy you started must be gone: run
   `ps -axo pid=,command= | grep TypeStats | grep -v grep`; only the owner's
   `~/Applications/TypeStats.app` may remain. End a test copy with
   `pkill -TERM -f "<its data dir>"`. Never quit by app name
   (`osascript -e 'quit app "TypeStats"'` also quits the owner's installed copy).
