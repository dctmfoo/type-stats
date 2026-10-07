# Prepare type-stats for a public repository and Homebrew releases

## What changed

- Audit fixes: the popup no longer reads every past day from the store on each redraw (which is
  every key press while it shows 7 or 30 days). `KeyCounter.history(days:)` keeps past days'
  rows until a flush writes to a past day or the day rolls over; today stays live. The wpm
  tooltip described the old burst estimate; it now describes the net steady-stretch estimate.
  `--simulate-typing` now clears modifier flags on its events: one full check run on a busy Mac
  lost every simulated typing stretch (keys counted, no wpm), which a held Command or Control
  key leaking into the new events explains; the next full run passed.
- Personal data: the share prototype samples, tests and checks used numbers and app names
  taken from the owner's own day; they are now made-up (Xcode, Mail, Google Chrome, Notes,
  Terminal). `docs/run.md` no longer names the owner's signing certificate, `.po/check.sh` runs
  the project's own `.po/bin/secret-scan.py` instead of a path on the owner's disk, a change
  record no longer links a private repository, and the brief's audience reflects publication.
- Public files: `README.md` with screenshots in `docs/images/` (rendered from sample data by
  `scripts/readme-screenshots.sh`, using the new `--no-test-banner` option), `LICENSE` (MIT),
  `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates.
- Pipeline, mirroring SimpAlarm: `.github/workflows/build.yml` (build, unit tests, bundle,
  launch smoke), `secret-scan.yml` (gitleaks over history), and `release.yml` (on a `v*` tag:
  universal build, Developer ID signing, notarization, GitHub release with zip, checksum and cask,
  and a commit of the cask to `dctmfoo/homebrew-type-stats` when `HOMEBREW_TAP_TOKEN` is set).
  `scripts/package-release.sh` and `scripts/render-cask.sh` do the packaging; `bundle-app.sh`
  takes `TYPESTATS_VERSION`, `TYPESTATS_BUILD` and `TYPESTATS_ARCHS`.
- `.gitignore` covers `dist/`, `.claude/settings.local.json` and certificate files.

## Checks

- Unit tests: `testPastDaysAreReadOnceWhileTodayStaysLive` (one store read for past days across
  ten redraws and a flush, today's presses still shown at once) and
  `testCountsFlushedAfterMidnightReachThePastDayOnce` (a past day's presses flushed after midnight
  are shown once, not lost or doubled), `testParsesNoTestBanner`, and the updated share text tests.
- `sh .po/check.sh` (all real-app checks, freshness and seam coverage).
- `sh scripts/package-release.sh 0.1.0` without credentials: universal (x86_64 arm64) app, ad hoc
  signed, zip, checksum and cask rendered.
- `actionlint`, `shellcheck` on the new scripts, `gitleaks git` over the full history.

## Methods used

- tdd: the history cache tests were written against the cache's two failure modes (stale past
  days, double counting after midnight).

## Friction

None.

## Harness impact

`docs/run.md` gained the release section, two commands and the `--no-test-banner` seam row;
`.po/check.sh` uses the vendored secret scan.

## Limits

- Signing and notarization in CI are not exercised until the repository has its secrets and a
  tag is pushed.
- Git history still holds the personal details removed from the tree here; it was not rewritten.
