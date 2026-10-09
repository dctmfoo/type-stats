# Run type-stats

## Required local tools
- macOS 14 or later
- Xcode with command line tools selected (`xcode-select -p`); Swift 6 or later
- Python 3 (checks only)

## Commands (from the project folder)
```sh
swift build                    # compile (debug)
swift test                     # behavior tests (XCTest + Swift Testing)
sh scripts/bundle-app.sh       # build .build/TypeStats.app (release, signed with your Apple Development identity)
open .build/TypeStats.app      # launch; a keyboard icon appears in the menu bar
sh scripts/app-smoke.sh        # real-app check (needs the bundle above)
sh scripts/exclude-check.sh    # excluded-apps check (needs the bundle above)
sh scripts/pause-check.sh      # pause counting check (needs the bundle above)
sh .po/check.sh                # full project check (the full real-app check)
sh scripts/install-app.sh      # build, quit any running copy, install to ~/Applications and open it
sh scripts/readme-screenshots.sh   # render docs/images/ from made-up sample data
sh scripts/package-release.sh 0.2.0  # release zip and Homebrew cask (see Releases and Homebrew)
```
`sh scripts/bundle-app.sh debug` builds a debug bundle instead.

## Everyday use: run the installed copy
Run `sh scripts/install-app.sh` once (and again after each update). It builds the app,
quits any running TypeStats (counts are saved), copies it to
`~/Applications/TypeStats.app` and opens that copy. Use that installed copy from then
on, not `.build/TypeStats.app`: "Start at login" remembers the app's location, and
`.build/` is replaced by every build and check. The install script also keeps the Input
Monitoring approval working across reinstalls (see Signing and Input Monitoring).

## Signing and Input Monitoring
macOS ties the Input Monitoring approval to the app's code identity (its designated
requirement). An ad hoc signature (`codesign --sign -`) makes that identity the hash of the
binary, so every build looked like a new app: the list in System Settings still showed
TypeStats switched on, but the grant belonged to the previous build and the popup said
"Permission needed".

`scripts/bundle-app.sh` therefore signs with a local `Apple Development` certificate from the
login keychain, whose designated requirement names the bundle id and that certificate, not the
binary, so it is identical on every rebuild:
```
designated => identifier "local.typestats.TypeStats" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: Your Name (TEAMID1234)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
```
Check it with `codesign -dr - .build/TypeStats.app`.
- Identity choice: the first `Apple Development: ...` certificate by name, skipping Xcode's
  "Created via API" ones. Developer ID and distribution certificates are never used and no
  certificate is created. `TYPESTATS_SIGN_IDENTITY="<certificate name or SHA-1>"` picks another
  identity; `TYPESTATS_SIGN_IDENTITY=-` forces ad hoc.
- With no usable identity the script prints a message and signs ad hoc (the old behaviour: the
  approval is lost on every rebuild).
- `scripts/install-app.sh` compares the installed copy's designated requirement with the new
  build's. When they differ (the one-time switch from ad hoc to stable signing, or another
  identity) it runs `tccutil reset ListenEvent local.typestats.TypeStats`, which clears only
  this app's Input Monitoring entry; turn TypeStats on once more when the popup asks. After
  that, reinstalls keep the same requirement and the approval stays.
- Test copies run with `--no-tap`, never ask for Input Monitoring and are unaffected.

## Releases and Homebrew
`TYPESTATS_VERSION` and `TYPESTATS_BUILD` set the bundle's version (default `0.1.0` and `1`), and
`TYPESTATS_ARCHS="arm64 x86_64"` makes `scripts/bundle-app.sh` build a universal binary.

`sh scripts/package-release.sh 0.2.0` builds the universal app, signs it with the Developer ID
named by `DEVELOPER_ID_APP_SIGNING_IDENTITY` (hardened runtime, secure timestamp), notarizes and
staples it (`NOTARYTOOL_KEYCHAIN_PROFILE`, or `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` and
`APPLE_TEAM_ID`), and writes `dist/releases/0.2.0/`: `TypeStats-0.2.0.zip`, its `.sha256` and the
cask type-stats.rb (from `scripts/render-cask.sh`). Without those variables it still runs,
ad hoc signed and not notarized, which is only good for trying the packaging.

Pushing a tag `v0.2.0` runs `.github/workflows/release.yml`, which does the same on a GitHub
runner with the repository secrets listed at the top of that file, attaches the zip, checksum and
cask to the GitHub release, and commits the cask to the tap repository
(`dctmfoo/homebrew-type-stats`) when `HOMEBREW_TAP_TOKEN` is set. Users install with
`brew install --cask dctmfoo/type-stats/type-stats`. A Developer ID build keeps one designated
requirement across releases, so Input Monitoring stays approved after `brew upgrade`.
The tap repository's README is kept here as `packaging/homebrew/README.md`.

## App updates
The popup footer shows the running version. Opening the popup checks the published Homebrew
cask at most once an hour; it becomes "Update available" when that cask is newer. Clicking
the version opens App Updates with Current version, Latest version and release status.
"Check for Updates" requests a fresh check. When a newer cask exists the button reads
"Update from Homebrew". Checks read the version line from the published tap cask at
https://raw.githubusercontent.com/dctmfoo/homebrew-type-stats/HEAD/Casks/type-stats.rb.
This is the exact cask the release workflow publishes, so an unshipped GitHub tag is not offered.

Updating locates Homebrew at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`, refreshes its
metadata, confirms the running bundle is the installed cask target, and upgrades only
`dctmfoo/type-stats/type-stats` using `--no-quit`. Progress stays visible and errors leave
TypeStats running. Once the installed bundle is at least the offered version, macOS launches
a new instance; only a confirmed launch ends the old instance. Counts are saved before restart.
There are no silent updates. Updates require the Homebrew-installed app and a Homebrew version
supporting `--no-quit`; an unsupported flag is shown as an error.

## Start at login
The popup's footer has a "Start at login" switch next to Quit. On registers TypeStats
as a login item (`SMAppService.mainApp`), off removes it, and the switch shows the
status macOS reports, so a change made in System Settings > General > Login Items shows
up the next time the popup opens. If macOS needs approval first, the footer says so and
offers "Open Login Items". In test mode (`--no-tap`) the switch only changes an
in-memory setting, so a test build can never add itself to login items.

## First launch
macOS asks for Input Monitoring. Allow it in System Settings > Privacy & Security >
Input Monitoring for TypeStats, then reopen the app. Until then the popup shows
"Permission needed" with a button that opens that settings page. Builds signed with an
Apple Development identity keep the approval across rebuilds; ad hoc builds do not
(see Signing and Input Monitoring).
Clicks need no extra permission: they arrive through the same event tap, so they are
counted whenever keys are.

## What is counted
- One count per key press (keyDown) in the frontmost app, including shortcuts such as
  Cmd+C. Holding a key down (autorepeat) counts once. Modifier keys pressed alone
  (Shift, Cmd, ...) are not counted.
- Keys typed into a terminal count under the terminal app (Terminal, Ghostty, ...),
  not the program running inside it (for example Claude Code CLI).
- macOS hides keys typed into password fields (secure input) from all apps, so those
  are not counted.
- One count per mouse click (mouse-down) for left, right and other buttons, and for
  trackpad tap-to-click. A double click counts 2. Mouse up, drag, movement and scroll
  are not counted.
- A click counts for the app that owns the window under the pointer, not the frontmost
  app: TypeStats asks macOS which window that click hits (which skips click-through
  overlays such as the Dock's invisible full-screen window), then falls back to the
  topmost visible normal or floating window there, then to the frontmost app.
  The pointer position is used only for that lookup and is never stored.
- Menu bar and Dock clicks go to whichever owner that lookup finds. The menu bar itself
  belongs to the system, so clicks on app menus (File, Edit, ...) count for the
  frontmost app; a status icon owned by an app may count for that app. Dock clicks
  normally count for Dock. Clicks on the bare desktop count for the system app that owns the
  desktop window there (usually Dock).
- Counts are saved every 3 seconds and when the app quits.
- Every key press and click is also counted in its local hour (0 to 23) for the
  "By hour" chart. Counts saved before this version have a day but no hour; the Today
  view says how many keys and clicks today have no hour instead of guessing one.

## Views
The popup opens on "Today" and has "Today | 7 days | 30 days" at the top.
- Today: keys, clicks and typing speed totals, keys (bars) per hour,
  and the top apps with keys, clicks and typing speed on each row.
- 7 days / 30 days: totals for the period (today included, so 7 days is today and the
  6 days before), keys (bars) per day, and the top apps over the
  period. Days from before this version appear normally; only their hours are missing.

The popup is one fixed size for all three views (the same width, and a height that
reserves room for the chart, the one-line "no hour" note and up to 8 app rows), so the
menu bar window never resizes or moves when you switch views or counts tick. Fewer apps
leave blank space under the list. Layout changes are not animated.

## Share
The popup footer has a Share button next to Quit. Its menu works on the period being
viewed (Today, 7 days or 30 days):
- Copy image: card A (big numbers, chart, top 3 apps, TypeStats footer) as a PNG on the
  clipboard (a TIFF too, for apps that only read that). The card is 1200x630 points
  drawn at 2x, so 2400x1260 pixels.
- Copy text: one line, e.g. "Today: 7,120 keys · 665 clicks · 58 wpm. Top: Xcode 3,840 ·
  Mail 1,215 · Chrome 960. via TypeStats" ("Last 7 days:" / "Last 30 days:" for the
  others). Numbers always use commas. With fewer than 3 apps it lists what exists; with no
  typing speed yet the wpm part is left out; with no data it is "Today: 0 keys · 0 clicks.
  via TypeStats".
- Save image...: a save dialog in Downloads named `TypeStats-Today-2026-10-05.png`
  (`TypeStats-7-days-...`, `TypeStats-30-days-...`), PNG only.
The button briefly says "Image copied" / "Text copied" after a copy. Nothing is posted
anywhere; the card and line hold counts and app names only.

## Excluded apps
Click "Excluded apps" (next to "Top apps" in the popup) to open the Excluded apps page; "Back"
returns to the popup. The page lists the excluded apps, each with a Remove button, then the
apps to exclude from, each with an Exclude button: the top apps of the period being viewed,
then the other running apps (those with a Dock icon). The popup keeps its size.
- An excluded app is never counted: its key presses and clicks add nothing, not even typing
  time, and it gets no row for the day. A click counts for the app under the pointer, so a
  click on an excluded app's window is dropped (it does not fall back to the frontmost app).
- Counts saved before the exclusion stay in the totals, charts and history. Its row in
  Top apps shows "excluded" in place of its typing speed, and the button reads
  "Excluded apps (n)" while the list is not empty.
- Removing an exclusion counts the app again from then on. Nothing counted while it was
  excluded is recovered.
- The list is stored in the same store as the counts (bundle id and name only) and survives
  quitting and reopening. Stores from before this version upgrade in place with an empty list.
- Apps are identified by bundle id, so an app that is both running and in Top apps is listed
  once, under Top apps. TypeStats can be excluded like any app (its own popup clicks are
  counted otherwise).

## Pause counting
Under the totals the popup has a row that says "Counting" with a Pause button. Pause opens a
menu: 15 minutes, 1 hour, Until I resume.
- While paused, no key press or click is counted for any app (the event is dropped before
  any app lookup), typing speed gets no time added, and the row turns orange: "Paused until
  3:15 PM" (with the weekday when that is not today) or "Paused until you resume", next to a
  Resume button. One click on Resume counts again at once.
- The menu bar icon is a keyboard while counting and a pause sign while paused.
- A timed pause ends by itself at its end time; the popup and icon update within 3 seconds,
  but counting resumes exactly at the end time.
- The pause survives quitting and reopening TypeStats (and a restart of the Mac) until its end
  time; "until I resume" lasts until you click Resume. It is saved as an end time only, in
  `pause.json` next to the store (`~/Library/Application Support/TypeStats/pause.json`): no
  counts, apps, keys or text. If that file is deleted or unreadable, counting is not paused.
- The popup keeps one size whether paused or counting.
- The event tap stays on while paused (so resuming needs no permission prompt); everything it
  delivers is discarded before it is counted.

## Typing speed (wpm)
An estimate of net typing speed during steady writing. Text is never read.
- At the event boundary, each key-down becomes one coarse kind: typing character,
  Backspace/Delete, or other. The physical key code is discarded immediately.
- Letters, numbers, punctuation, Space and Enter count as one character each.
  Backspace and forward Delete remove one character, floored at zero within the current
  stretch. Cmd/Ctrl-modified keys, navigation, Tab, Esc and function keys end the stretch.
- A stretch continues with gaps strictly under 2 seconds and qualifies at 10 seconds
  from its first to last press. Shorter stretches contribute no characters or time.
  App changes, excluded or paused input, unknown timing and a new day break continuity.
- Once qualified, its full net count and duration contribute immediately. Further
  typing and corrections update the estimate, including after a periodic save.
- wpm = (net characters / 5) / qualifying minutes. The first character counts.
  Holding a key counts once, as in the key total. All keys still add to the keys total.
- Shown overall and per app, in history, sharing and `--dump-wpm`. Before a stretch
  qualifies the estimate is absent. A qualifying stretch with zero net characters is 0 wpm.
- Presses use the event's timestamp, so a busy app does not skew the timing.
- Older stored days retain their original estimates. Existing speed fields keep their
  names and now receive net characters and qualifying seconds. No history is recomputed.
  Periods spanning the change, and the upgrade day, combine the saved old totals with
  new totals by duration. A restart begins a fresh stretch and keeps qualified totals.
- This estimates physical typing, not produced text: paste, composition and deleting
  whole words are not measured as their text length. The app never reads that text.

## Data
Counts are stored locally in a SwiftData store at
`~/Library/Application Support/TypeStats/TypeStats.store`:
- one row per day and app: day, bundle id, app name, key count, click count, net
  characters and qualifying typing seconds for speed, with historical totals retained;
- one row per day, hour and app: day, hour, bundle id, key count, click count;
- one row per excluded app: bundle id and name.

Key codes, characters, text, the time of any single press and click positions are
never stored. Counts stay on this Mac; release checks send no counts or app names.
Older stores are upgraded in place on first launch: key and click counts are kept
unchanged, typing time starts at 0 and earlier counts have no hour. A daily goal saved by an
earlier version is ignored (the feature is gone) and does not stop the store from opening.

## Test seams (command line options)
| Option | Effect |
|---|---|
| `--data-dir <path>` | Use this folder for the store instead of the default |
| `--no-tap` | Do not start the event tap or ask for permission (test mode) |
| `--simulate-keys "bundleId:n,..."` | Feed n synthetic key presses per app through the same pipeline as the event tap, then save |
| `--simulate-text "bundleId:text"` | One synthetic key press per character, carrying that character; checks prove it is not stored |
| `--simulate-clicks "bundleId:n,..."` | Feed n synthetic clicks per app (cycling left, right, other button) through the same pipeline as the event tap, then save |
| `--simulate-self-clicks n` | Order a TypeStats window front without activating it, then feed n clicks at its centre with no app given, so the real under-pointer lookup attributes them (expected: `local.typestats.TypeStats`) |
| `--hold-flush` | Keep simulated presses unsaved until quit (proves quit saves them) |
| `--show-window` | Also show the popup contents in a normal window |
| `--snapshot <png>` | Render the popup view to a PNG after launch |
| `--simulate-typing "bundleId:keys:seconds,..."` | Feed timed key presses through the same pipeline: each segment spreads `keys` presses evenly over `seconds` (event timestamps, ending now); segments are separated by a 60 s idle pause. `A:300:60` gives about 60 wpm; segments under 10 seconds do not qualify |
| `--at yyyy-MM-ddTHH:mm` | Freeze the app's clock at this local time: simulated events land on that day and hour, and "today" (popup and dumps) is that day |
| `--view today\|week\|month` | Open the popup (and `--snapshot`) on that period |
| `--seed-nohour "bundleId:n,..."` | Before launch, add n keys and n clicks to today for each app with no hour (as counts from before hourly tracking look), so Today shows its "no hour" note |
| `--measure-views` | Open the popup in a borderless window that follows its content size (as the menu bar window does), switch through Today, 7 days, 30 days and Today again while counts arrive, print `step<TAB>fitting w<TAB>h<TAB>window x<TAB>y<TAB>w<TAB>h` after each, and exit. Every row must have the same numbers |
| `--share-copy image\|text --pasteboard <name>` | After simulating, copy the card or the line for `--view` to the NAMED pasteboard (never the general one; refused without `--pasteboard`) and exit |
| `--share-save <path>` | After simulating, write the 2400x1260 card for `--view` to that path (no dialog) and exit |
| `--pasteboard-read <name> [--pasteboard-png <path>]` | Print what a named pasteboard holds (`text`, `png`, `tiff` with pixel size) and release it, optionally saving the PNG; exit |
| `--ready-file <path>` | Write this file once startup, the simulated presses and clicks, and any `--snapshot` are done. `scripts/app-smoke.sh` waits on it after every launch instead of sleeping; if it never appears the smoke prints "app did not start counting" with a `sample` of the process. Not written by the exit-early seams (`--dump-*`, `--share-*`, `--measure-views` when it exits) |
| `--share-panel` | Open the Save image dialog at launch (what the menu's Save image... does) |
| `--exclude "bundleId,..."` | Before simulating, add these apps to the excluded list (the call the popup's Exclude button makes) |
| `--include "bundleId,..."` | Remove these apps from the excluded list (the Remove button's call), then simulate |
| `--excluded-page` | Open the popup (and `--snapshot`) on the Excluded apps page. In test mode (`--no-tap`) the running-apps list is left empty |
| `--dump-excluded` | Print the excluded list as `bundleId<TAB>name` and exit (no UI) |
| `--dump-counts` | Print today's counts as `bundleId<TAB>keys<TAB>clicks` and exit (no UI) |
| `--dump-hours` | Print today's `hour<TAB>keys<TAB>clicks` for hours with counts, then `nohour<TAB>keys<TAB>clicks` if some of today's counts have no hour, and exit |
| `--dump-history n` | Print the last n days ending today: `day<TAB>yyyy-MM-dd<TAB>keys<TAB>clicks` for every day (oldest first), `app<TAB>bundleId<TAB>keys<TAB>clicks` per app (most keys first), then `total<TAB>keys<TAB>clicks`, and exit |
| `--dump-wpm` | Print today's typing speed: `overall<TAB>wpm` (or `-`), then `bundleId<TAB>wpm` for apps with a speed, and exit |
| `--pause 15m\|1h\|until-resumed` | Start with counting paused, as choosing that item in the Pause menu does (the end time is counted from the app's clock, so `--at` makes it exact) |
| `--resume` | Clear any pause at launch (what Resume does); applied before `--pause` |
| `--resume-after n` | n seconds after launch, resume as a Resume click does (lets a check watch the menu bar icon change) |
| `--dump-pause` | Apply `--pause`/`--resume`, then print `paused\|running<TAB>end time or -<TAB>menu bar symbol<TAB>status text or -` and exit. A pause whose end time has passed (by `--at`) reads as `running` |
| `--no-test-banner` | With `--no-tap`, leave the "Key capture off (test mode)" line out of the popup, so `--snapshot` gives a clean screenshot (`scripts/readme-screenshots.sh`) |
| `--update-version <version>` | With `--no-tap`, fake the running version for update verification |
| `--update-cask <path>` | With `--no-tap`, read a local cask fixture instead of the published cask |
| `--update-brew <path>` | With `--no-tap` and `--data-dir`, use this executable instead of system Homebrew |
| `--updates-window` | With `--no-tap`, check then open App Updates; `--snapshot` renders that dialog |
| `--perform-update` | With `--no-tap`, check then run the same update action as the button; use a fixture brew for automated checks |
| `--update-relaunch-ready <path>` | A test relaunch writes this ready file, keeps `--no-tap` and its isolated data folder |
| `--login-status` | Print the real login item status (`enabled`, `disabled` or `requiresApproval`), read only, and exit |

Example: `open -n .build/TypeStats.app --args --data-dir "$PWD/.po/tmp/x" --no-tap --show-window --simulate-keys "com.apple.TextEdit:5" --simulate-clicks "com.apple.finder:3"`.
History example: `.build/TypeStats.app/Contents/MacOS/TypeStats --data-dir "$PWD/.po/tmp/x" --no-tap --at 2026-10-01T14:00 --simulate-typing "com.apple.TextEdit:300:60"`,
then `... --data-dir "$PWD/.po/tmp/x" --at 2026-10-04T18:00 --dump-history 7`.
The popup's expected pixel size (width x height at 2x) is one constant, `scripts/popup-size.txt`,
read by `scripts/share-check.sh` and `scripts/share-prototype-check.sh`; change it there when the
popup layout changes.
`kill -TERM <pid>` quits the app normally (counts are saved).

## Smoke
`python3 .po/bin/freshness.py` (run by `sh .po/check.sh`) runs these commands to prove this
page still matches the code: build, bundle the app, then one `--dump-counts` call against an
empty data folder (prints nothing for an empty store and exits 0, with no UI and no event tap).
```smoke
swift build
sh scripts/bundle-app.sh
mkdir -p .po/tmp/freshness-data
.build/TypeStats.app/Contents/MacOS/TypeStats --data-dir "$PWD/.po/tmp/freshness-data" --no-tap --dump-counts
```

If the terminal lacks Screen Recording permission, `screencapture` fails with
"could not create image"; use `--snapshot` instead.
