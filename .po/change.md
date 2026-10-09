# Fix the collapsed menu bar popup

## What changed

0.1.3 opened the real menu bar popup with only the picker, totals, Pause row and footer:
the hour chart, day chart, heatmap and Top apps were gone. The shared detail area was a
`ViewThatFits` with a `minHeight: 0` frame; the menu bar window offers no height, so it
picked the scrolling variant at 1 point tall. The popup is now laid out by `PopupLayout`
(Sources/TypeStats/PopupView.swift): pinned top, a scrolling detail area, pinned footer.
See [Views](../docs/run.md#views) for the display contract.

## Checks

Added `scripts/popup-real-check.sh` to `.po/check.sh`. See
[Test seams](../docs/run.md#test-seams-command-line-options) for its assertions and evidence limits.
Against the 0.1.3 source it fails: the window is 360x306 and the detail area 1 pt tall.
The old hosting-window checks passed on that source because a hosting window sizes differently.

## Limits

See [Required local tools](../docs/run.md#required-local-tools) for check prerequisites.
