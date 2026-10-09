# Weekly typing heatmap

The 7-day popup and shared image now show seven dated rows by 24 local-hour columns.
Grey means zero keys. Four blue shades scale against the busiest hour in the shown week;
even one real key differs from zero. Outlined cells mark today's future hours.
The peak line gives a day and hour, with the number of ties when there is more than one.
A "Based on X of Y keys" note reports older keys that have no saved hour.

The popup stays 360 points wide and keeps its existing height across periods. Its weekly
Top apps area scrolls to all eight apps. Today and 30 days keep their full app-list space.
The weekly share image remains 2400x1260 pixels. Counting and storage are unchanged.

## Verification

Four focused unit tests cover live and saved hourly counts, rollover without an event,
flush and reopen parity, legacy counts, peak ties and shade thresholds. The project check
now seeds an isolated real store and compares all 168 cell colours in both renders. A
purposefully broken shade mapping made that check fail before the final passing run.

Native-window captures show all eight fixture apps across top, middle, lower and bottom
scroll positions. Every test launch used --no-tap and an isolated data directory. The
owner's data was never read or used. No test copy remains running.

Proof and screenshots are retained outside the worktree in the task evidence directory
and will be attached to the pull request during the separate validation-and-shipping step.
The actual event tap and menu-bar opening were not exercised by this seeded render check.
The existing store combines repeated daylight-saving hours into one local-hour bucket.
