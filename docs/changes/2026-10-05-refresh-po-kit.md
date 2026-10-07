# Refresh po-kit in type-stats to claude-bootstrap-plugin 34c5f1b

## What changed

type-stats now carries the po-kit fixes that merged as claude-bootstrap-plugin PR 7
(main 34c5f1b). Updated by running
the kit's `scripts/init.py` at the project root; `/po-kit:init` was not run. No product code changed.

- `.po/bin/` matches the kit: `freshness.py` is the new version (it reads a path outside the
  project as one location, covers seams, checks retired terms); `evidence.py` and
  `harness-due.py` are new. `.po/harness-review.md` is the new harness review brief. `.po/methods/`
  and `.po/change.md` are unchanged from the kit. There is no `.po/harness.json` yet: no harness
  review has run.
- Seam coverage moved to the kit's mechanism. `scripts/seam-coverage.sh` is removed and
  `scripts/manual-seams.txt` is now `.po/manual-seams.txt` (same one line, `--share-panel`).
  The kit check covers the same seams: it reads the same `docs/run.md` table rows, accepts a
  flag found in `scripts/` checks, `.po/check.sh` or a smoke command, and accepts the manual
  list; it is stricter in matching a whole flag and in failing a manual line whose flag left
  the table.
- `.po/stale-terms.txt` is new and lists `mcp__po-kit__prove`.
- `.po/check.sh` no longer calls `scripts/seam-coverage.sh`; a comment says freshness covers it.
- `docs/run.md`: the two rewordings made at install (pause.json and the Data section) are
  undone, because the kit now reads `~/Library/Application Support/...` as one location. The
  Smoke section stays.
- `AGENTS.md` is byte-identical to before: the rules block init.py inserted was removed on
  purpose (decision: AGENTS.md keeps only its two project lines). `CLAUDE.md` and
  `.claude/settings.json` were already right.

## Checks

- `python3 .po/bin/freshness.py`: passes (2 recipe files). With `.po/manual-seams.txt`
  moved away it fails naming `--share-panel`, so seam coverage fails when a seam is uncovered;
  it passes again once the file is back.
- Every file under `.po/bin/`, `.po/methods/` and `.po/harness-review.md` compared equal to the
  kit at 34c5f1b.
- `python3 .po/bin/change-record.py`: this record passes.
- `sh .po/check.sh`: passes in full, including freshness, the smoke block, the app checks and
  the leak check (no test copy of the app left running).

## Methods used

- none

## Friction

- init.py inserts the AGENTS.md rules block every run, so it was reverted by hand again
  (`git checkout AGENTS.md`).
- `scripts/leak-check.sh` stays as the project's own check; the kit has no equivalent.

## Harness impact

Updated `.po/check.sh` (seam-coverage line removed), `docs/run.md` (two spans restored),
`.po/manual-seams.txt` (moved) and `.po/stale-terms.txt` (new). Left alone: `docs/brief.md`,
the verify skill and `AGENTS.md`. The verify skill and `docs/run.md` still do not mention the
harness review tools; `.po/check.sh` still does not run `change-record.py` or `proof.py`.

## Limits

`harness-due.py` reports not due (this is the second change record). Freshness proves cited
paths exist and seams are driven or listed, not that the prose is true. The stale-terms
list only catches `mcp__po-kit__prove`; other retired names are not listed.
