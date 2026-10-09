# Weekly typing heatmap

Added weekly typing hours to the 7-day popup and shared image. The display contract is
in [Views](../run.md#views); export behavior is in [Share](../run.md#share).

## Verification

Focused unit tests cover live and saved hourly counts, rollover without an event,
flush and reopen parity, legacy counts, peak ties and shade thresholds. The project check
now seeds an isolated real store and compares all 168 cell colours in both renders. A
purposefully broken shade mapping made that check fail before the final passing run.

Native-window captures show all eight fixture apps across top, middle, lower and bottom
scroll positions. Every test launch used --no-tap and an isolated data directory. The
owner's data was never read or used. No test copy remains running.

Proof and screenshots are retained outside the worktree in the task evidence directory
and will be attached to the pull request during the separate validation-and-shipping step.
The actual event tap and menu-bar opening were not exercised by this seeded render check.
