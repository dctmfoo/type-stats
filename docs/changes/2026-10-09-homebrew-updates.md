# Show releases and update through Homebrew

The popup footer now shows Version followed by the running bundle version, changing to
Update available when the published cask is newer. Clicking it opens App Updates with
current/latest versions, release status and Check for Updates or Update from Homebrew.
The source is the version line in the published tap cask at
https://raw.githubusercontent.com/dctmfoo/homebrew-type-stats/HEAD/Casks/type-stats.rb.
The release workflow writes that exact cask; GitHub tags that are not in the tap are not offered.

The updater locates brew explicitly, verifies that the running app is the installed cask
target, refreshes Homebrew metadata and upgrades only dctmfoo/type-stats/type-stats with
--no-quit. Output goes to temporary files to avoid pipe deadlocks. The installed cask and
bundle must reach the offered version before restart. Counts are saved and input delivery
in the old instance is suspended while macOS opens a new instance. The old instance exits
only after a confirmed replacement launch; failed launches resume input in the old instance.
Failed upgrades keep the app and show an error. No silent update or updater framework was added.

The final full project prove passed: 69 XCTest tests and 10 Swift Testing tests, signed bundle,
app smoke, WPM, share prototype, share, exclusions, pause, updates and leak checks. The new
bundle check covers both footer/dialog states, malformed release data, failed Homebrew calls,
explicit arguments and actual process replacement preserving seven seeded key counts.
A deliberately broken footer build failed the same full check with
`FAIL updates: footer indicator missing`. Restoring it produced a passing exact-file receipt.

Native verification drove the footer in the bundled app's show-window seam. Clicking
Update available opened App Updates. Clicking the update button produced a progress
message and disabled action, then a fixture error while the app stayed running. An
up-to-date dialog read the live published cask; clicking Check for Updates read it again
and retained the latest-release status. All captured app windows were inspected.

Proof is outside this disposable worktree in the assigned ts-update-available-u1 task data
folder: proof.json, proof/check-red.log, proof/check-green.log and proof/live-updates/.
Screenshots there include up-to-date.png, up-to-date-after-check.png, footer-available.png,
update-available.png, updating.png and upgrade-failed.png. The main automated fixture run
is retained in proof/updates.gOKyyC/.

The actual version-to-version Homebrew upgrade remains unproved. The tap, sole release and
installed cask are all 0.1.0; the controlled brew executable cannot substitute for real
Homebrew installation proof. Firstmate must arrange an authorized older installation or
newer release before that acceptance gate can be completed. Screenshots are ready for
attachment to the eventual PR, but no PR has been created or pushed from this worktree.
A native menu-bar click did not expose a capturable popup here; the identical PopupView
in the real show-window seam and its footer click were driven. Physical input and Input
Monitoring persistence across a signed release upgrade were not tested.

All test copies started here were terminated. The pre-existing owner's installation at
/Applications/TypeStats.app was retained. That observed path differs from the project
cleanup instruction's ~/Applications path and is reported for firstmate to resolve.
