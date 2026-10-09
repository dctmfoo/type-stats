# Show weekly typing hours in the popup and shared image

## What changed

The 7-day view has a seven-date by 24-hour typing heatmap beneath By day. The shared
7-day image uses the same counts, shade mapping, dated peak line and coverage note.
Zero is grey. Positive counts use four blue quartiles of the busiest shown cell.
Future hours today have outlines, and keys saved without an hour remain unplaced.
Today's live counts are included once; pending counts from an ended day are included
once before and after a flush. Past hourly reads are cached without changing storage.
The 7-day popup grows by the heatmap and keeps the full Top apps list, capped at the visible
screen height. The heatmap has light and dark palettes. Other periods keep their layout.

## Checks

Four focused unit tests cover dimensions, multiple apps, live counts, rollover without
an event, flush/reopen parity, legacy coverage, empty weeks, tied peaks and shade edges.
A deliberately broken render mapping failed the full project check at heatmap-probe.
The new render check compares all 168 cell centres in both the popup and shared image,
including zero, the four positive shades, future cells and an unflushed hour.
Native-window screenshots prove that all eight apps can be reached by scrolling.
Final full-check and exact-file receipts are retained in the assigned task data folder.

## Methods used

- review: traced saved, live and rollover aggregation before checking real render output.
- boundary-discipline: the core snapshot decides future cells, coverage and peak ties; both views share it and the same palette.

## Friction

ImageRenderer omits the native scrolling app list. Native window captures and real wheel
events proved reachability instead. Test binaries need a persistent foreground session;
a short-lived shell killed earlier copies before Peekaboo could resolve their PIDs.
Peekaboo's negative-coordinate parsing and window move were unreliable, so the final
scroll proof targeted the exact test window through CoreGraphics and window-id capture.

## Harness impact

Added heatmap-check and its stdlib-only PNG pixel probe to the full check. Added the
no-tap-only dark-snapshot seam for dark popup/window proof. Test data and receipts reside
outside the worktree through ignored .po/tmp and proof.json symlinks.

## Limits

The existing store combines repeated daylight-saving hours into one local-hour bucket.
Historical hourly gaps are reported, never inferred. The native menu-bar opening and
physical event tap were not driven; all renders and scrolling used isolated seeded data
with --no-tap. ImageRenderer popup PNGs omit the scrolling Top apps rows; live captures show them.

## Review

Intent: make the most active typing hours visible in the 7-day popup and shared image
using actual hourly counts and clear shading.
Act on: the original heatmap slot let the legacy coverage note overlap Top apps. Increased
the slot, fixed row-label height, adjusted share scale and inspected native and exported
renders. A repeated peak must not imply a unique winner; name the first and state the
total number tied. A stale day at midnight must not double-count pending hours; refresh
the day before building the snapshot and test before and after flush/reopen.
Consider: the 7-day popup is taller than the other periods; Top apps scroll only past the visible screen height.
Noted: native event-tap and actual menu-opening proof remain outside this seeded feature check.
Dismissed: a storage migration or inferred hours would add risk and fabricate evidence.
