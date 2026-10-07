# Count net characters only during steady writing

## What changed

Option C now drives every WPM display. The event boundary immediately classifies physical
keys into typing character, Backspace/Delete or other and discards the key identity.
Cmd/Ctrl combinations are other. Text is never read. Each app's typing stretch qualifies
at 10 seconds, with gaps strictly under 2 seconds. Typing adds characters, deletion removes
one with a zero floor, and non-typing keys end continuity. The first character counts.
Only qualifying net characters and first-to-last duration contribute to speed.

Key and click totals and hourly counts are unchanged. Existing daily `burstCount` and
`activeSeconds` fields now receive qualifying net characters and seconds. Their schema,
names and defaults stay unchanged, so old stores load. Historical totals are never
rewritten. Old estimates retain the existing 5-second aggregate display floor. A period
spanning this change, including the upgrade day, combines saved old and new totals by
duration. Restarts begin new stretches while retaining qualified totals.

## Checks

The failing-before `SteadyTypingTests.testShortReplyDoesNotProduceSpeed` reported
`XCTAssertNil failed: "24.0" - 9.5-second reply must not produce WPM`.
The initial fixture used a fabricated uptime that the clock interpreted as mach ticks;
using the real uptime clock made the failure measure the intended threshold.

The unit suite covers coarse classification, Cmd/Ctrl exclusion, corrections after a
flush, per-stretch floors, exact 10-second qualification, strict 2-second gaps, independent
short stretches, app/day/paused/excluded/untimed boundaries, and old speed values loading
unchanged. The real bundle check in `scripts/wpm-check.sh` rejects short replies, checks
unchanged key totals, reopens qualified speed, and exercises sharing for every period.
The deliberately broken bundled build with a 5-second threshold failed with
`FAIL steady WPM: two 9.5-second replies contributed speed`. Restoring 10 seconds made
the full project prove pass: Swift build, 62 XCTest tests, 10 Swift Testing tests, signed
release bundle, app-smoke, steady WPM, share prototype, share, exclusions, pause and leak
checks. The passing receipt and complete log are in the task data folder as proof.json
and prove.log. Popup and shared-card screenshots were inspected: 40 short-reply keys
with no WPM; after qualification, 91 keys and 61 WPM overall, per app and in the week card.
Only the owner's installed copy remained running.

## Methods used

- architect: compared live contribution deltas with deferred completed-stretch storage; chose deltas so existing readers and periodic saves share one total.
- tdd: captured the short-reply failure before implementing the stretch threshold.
- blast-radius: traced all WPM consumers to stored daily totals and exercised history, sharing and persistence.
- review: checked privacy boundaries, corrections across flushes, historical meaning and continuity resets.

## Friction

The Apple docs export search had no matching symbol and the configured offline DocSetQuery
folder was absent on this Mac. Classification uses the installed macOS SDK HIToolbox
Events.h virtual-key constants and [Apple's CGEventFlags documentation](https://developer.apple.com/documentation/coregraphics/cgeventflags). Check fixtures and
proof are retained outside this disposable worktree under the authorized task data folder.
The existing project check writes fixtures via .po/tmp, temporarily routed there.

## Harness impact

Added `scripts/wpm-check.sh` to `.po/check.sh`. Updated the smoke WPM numerator to include
the first character, and updated existing speed tests for the chosen behavior. Updated
`docs/run.md` and the brief's outdated timing-only description. The verification skill's
launch and cleanup procedures still apply unchanged.

## Limits

The event tap with real Input Monitoring and physical typing was not driven. Synthetic
CGEvents exercise the same classifier/pipeline, and the real bundle exercises the output
and persistence paths. Physical key kinds cannot reveal text length after composition,
paste or word deletion. Option D and new UI are outside this change.

## Blast radius

The key safety fact is that WPM readers consume the same AppCount/History totals, while
key and hour counts use independent fields. Core integration tests run the counter through
flush and reload; bundle checks cover per-app/overall dumps and all shared periods. No
schema migration, historical recomputation or key-text storage was added. The accepted
risk is mixed old/new estimates for periods spanning the change; those retain saved totals
because raw historical typing is unavailable and rewriting history is explicitly excluded.

## Review

Intent: estimate net speed from steady writing while preserving all key totals, past
history and the counts-only privacy contract.

Act on: preserve old valid estimates shorter than 10 seconds by retaining the aggregate
5-second floor and gating new stretches before accumulation. Corrections after periodic
saves update totals with a negative character delta, tested through store reopen.

Consider: none. Noted: physical-key estimation limits described above. Dismissed: changing
stored field names would add migration work without changing the requested behavior.
