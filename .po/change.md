# Show app versions and update through Homebrew

## What changed

The popup footer shows its running version or Update available. App Updates shares the
same state, lists current/latest versions and offers Check for Updates or Update from
Homebrew. The update source is the tap's published cask. Homebrew is located explicitly;
its upgrade uses --no-quit, and the old process exits only after replacement launch succeeds.

## Checks

Four focused AppUpdate unit tests passed. A deliberately broken footer build failed the
full project check with `FAIL updates: footer indicator missing` after existing app checks
passed. The final full check result and exact-file receipt are retained in the task data
folder. The bundle check exercises dialog/footer states, malformed release data, failed
upgrades and real process relaunch with seven seeded key counts preserved.

## Methods used

- review: traced upgrade, data-save and launch failure paths before final proof.
- boundary-discipline: parse release versions and Homebrew responses at the service boundary; keep the shared update state independent of AppKit.

## Friction

The configured DocSetQuery scripts are absent; the installed offline Apple docset index
and the installed SDK/build establish the NSWorkspace signature. ImageRenderer omits
native AppKit button drawing, so the update action uses a SwiftUI button label/background.

## Harness impact

Added update-check to the full project check and documented guarded update test seams.
The footer increases popup height from 1429 to 1467 pixels; the shared size expectation
was updated. The fixture ignore pattern also ignores a .po/tmp symlink, allowing test
output to reside in the assigned external task directory.

## Limits

The controlled brew executable proves command arguments and failure handling, not a real
Homebrew version upgrade. The published cask, the sole release and the installed cask
are all 0.1.0. Real upgrade proof needs an authorized older install or a newer published
release. Screenshots and the remaining proof boundary are detailed in the change note.

## Review

Intent: expose releases in the existing popup and support a requested Homebrew upgrade
and reliable restart while preserving counts.
Act on: Homebrew's quit stanza could kill the updater; use --no-quit. A successful command
can be a no-op; verify installed metadata and bundle version before restart. The old
instance could accept input while its replacement opens; suspend its event delivery,
save counts and resume on a failed launch. Preserve the ready-file error diagnostic.
Consider: none.
Noted: real version-to-version upgrade requires release/install conditions absent here.
Dismissed: a generic updater framework is unnecessary for this single Homebrew cask.
