# type-stats

Native macOS menu bar app (Swift package) that counts key presses and clicks per app.

- Product brief and "Done means": docs/brief.md
- Build, run, test seams and data location: docs/run.md
- Answered and open product decisions: docs/decisions.md
- Build and test: `swift build`, `swift test`, `sh scripts/bundle-app.sh`
- Project check: `sh .po/check.sh`
- Real-app verification: the `verify` skill in .claude/skills/verify
- Temporary verification fixtures live under .po/tmp/
Run `sh .po/check.sh` before every commit, including UI-only changes.
Quit every test copy of the app you start; only `~/Applications/TypeStats.app` may be running when you finish.
