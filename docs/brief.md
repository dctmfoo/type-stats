# Brief: type-stats

## In the person's words
"I want build a mac app which captures number of keys i press and stats about that.
i type a lot and i just want to capture some stats on that. for example, i type in
claude code cli , claude code desktop, chatgpt desktop app etc a lot."

## Audience
Started for the owner, alone, on their own Mac. Published (2026-10-08) as an open-source app
anyone can install with Homebrew or build from source.

## Problem
The owner types heavily across AI tools and wants to see how much, and where.

## First small version
A menu bar app that counts key presses per frontmost app and shows today's total
and the top apps in a menu bar popup. It stores counts only; it never records which
key was pressed or any text. Counts persist across app restarts.

Known limit: keys typed into a terminal (for example Claude Code CLI) are counted
under the terminal app (Terminal, Ghostty, iTerm2, etc.), because macOS reports the
frontmost app, not the program running inside a terminal.

## Agreed stack
Native macOS app: Swift 6, SwiftUI `MenuBarExtra` popup, Swift Charts for graphs,
SwiftData for local history. Built as a Swift package from the command line and
wrapped in a signed (ad hoc) `.app` bundle, because macOS Input Monitoring
permission attaches to an app bundle. Key presses are observed with a listen-only
event tap (Input Monitoring permission). Agreed 2026-10-04.

## Done means
1. While the app runs, every key press in any app adds exactly 1 to that app's
   count for today, and no key codes or text are stored anywhere.
2. The menu bar popup shows today's total and the top apps by key count, with a
   Swift Charts bar chart.
3. Counts survive quitting and reopening the app.
4. (Added 2026-10-04) Mouse clicks (left, right, other buttons, trackpad taps) are
   counted per app under the pointer, shown side by side with keys: a clicks total
   next to the keys total and keys + clicks on each app row. No click positions stored.
5. (Added 2026-10-04) History of the last 7/30 days, today's keys per hour, an
   estimated net typing speed from steady stretches of at least 10 seconds, and a "Start at login" toggle.
6. (Agreed 2026-10-05) A Share button in the popup for the period being viewed
   (Today, 7 days, 30 days): Copy image (the full card: big numbers, chart, top 3
   apps), Copy text (a one-line summary), and Save image (download the card as a PNG).
7. (Added 2026-10-05) An Excluded apps list in the popup (for example a password manager).
   The owner can exclude one of the current top apps or a running app, and remove an
   exclusion. Key presses and clicks in an excluded app are never counted (no row, no
   typing time); its earlier history is kept and the app is marked excluded; the list
   survives quitting and reopening the app.
8. (Added 2026-10-05) A Pause control in the popup: pause for 15 minutes, 1 hour, or until
   resumed. While paused, no key presses or clicks are counted for any app; the menu bar
   icon and the popup show the paused state and when counting resumes; resuming is one
   click. The pause survives an app restart until its end time. Only the end time is saved.
9. (Added 2026-10-09) The popup footer shows the running version or "Update available".
   Clicking it opens App Updates with current/latest versions and a release status.
   A requested Homebrew update shows progress, restarts into the installed update, and
   leaves the running app available if upgrading or launching the replacement fails.
10. (Added 2026-10-09) Show weekly typing hours in the 7-day popup and shared image,
    following the [heatmap contract](run.md#views).
