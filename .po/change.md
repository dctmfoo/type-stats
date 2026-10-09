# Fix the collapsed menu bar popup

## What changed

0.1.3 opened the real menu bar popup with only the picker, totals, Pause row and footer:
the hour chart, day chart, heatmap and Top apps were gone. The shared detail area was a
`ViewThatFits` with a `minHeight: 0` frame; the menu bar window offers no height, so it
picked the scrolling variant at 1 point tall. The popup is now laid out by `PopupLayout`
(Sources/TypeStats/PopupView.swift): pinned top, a scrolling detail area, pinned footer.
It takes its size from the 580-point detail height and the screen cap, never from the height
the window offers. See [Views](../docs/run.md#views) for the unchanged display contract.

## Checks

`scripts/popup-real-check.sh` (in `.po/check.sh`) opens the real popup from the status item
of the bundled app, presses Today, 7 days and 30 days, and requires one window frame, a detail
area of at least 400 pt, and the chart, heatmap, Top apps and footer text in a window
screenshot, on a tall screen and with `--screen-height 700`. Against the 0.1.3 source it
fails: the window is 360x306 and the detail area 1 pt tall. The old hosting-window checks
passed on that source because a hosting window sizes differently.

## Limits

The check moves the real mouse and needs Accessibility and Screen Recording permission,
cliclick and a status item that is not hidden behind the notch.
