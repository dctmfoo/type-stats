# Install po-kit v2 in type-stats (methods, change records, freshness check)

## What changed

type-stats now has the shared po-kit assets the removed v1 harness never replaced:
`.po/bin/` (freshness, change-record, proof and secret-scan scripts), `.po/methods/`
(architect, blast-radius, review, tdd, principles and the verification-skill methods),
`.po/change.md` (the change-record template) and `docs/changes/` (this is its first record).
Installed by running the kit's `scripts/init.py` (claude-bootstrap-plugin at origin/main
4ab9897) at the project root; `/po-kit:init` was not run, so the brief, run recipe and verify
skill are untouched apart from the edits below.

- `CLAUDE.md` is new: one line, `@AGENTS.md`, so Claude Code loads the project instructions.
- `.claude/settings.json` gains `"autoMemoryEnabled": false`; nothing else changed there.
- `AGENTS.md` is byte-identical to before: the rules block init.py appends was removed on
  purpose (decision: AGENTS.md keeps only its two project lines).
- `.po/check.sh` runs `python3 .po/bin/freshness.py` right after the secret scan.
- `docs/run.md`: three code spans with a space inside (`~/Library/Application Support/...`)
  and the bare `pause.json` span tripped freshness as missing files. They now name the files in
  plain prose and cite only `~/Library/Application Support`, so the text says the same thing.
  A new "Smoke" section holds the `smoke` block: `swift build`, `sh scripts/bundle-app.sh`, and
  one `--dump-counts` call against an empty data folder under `.po/tmp/`.

## Checks

- `python3 .po/bin/freshness.py`: failed first with 3 false positives and a missing smoke block;
  passes after the rewording and the smoke block (2 recipe files).
- `sh .po/check.sh`: passes in full with freshness first, including the app, share, exclude,
  pause and goal checks and the leak check. The first run stalled on a macOS removable-volume
  permission dialog for the test copy of the app; it passed once Allow was clicked.
- `python3 .po/bin/change-record.py`: this record passes.
- `sh scripts/leak-check.sh` (last step of `.po/check.sh`): no test copy of the app left running.
- No product behavior changed, so no new behavior check was added.

## Methods used

- none

## Friction

- init.py's AGENTS.md rules block conflicts with the decision to keep AGENTS.md at two project
  lines, so it was reverted by hand after init ran.
- freshness.py treats a space inside a code span as two words, so any path under
  `Application Support` reads as a missing file. The kit is being fixed in a separate task; until
  then recipes cannot put such a path in one code span.
- The smoke block makes `.po/check.sh` build and bundle the app once more (about 25 seconds).

## Harness impact

Updated `.po/check.sh` (freshness line) and `docs/run.md` (spans reworded, smoke section).
Left alone on purpose: `docs/brief.md`, the verify skill, `AGENTS.md`, and the rules block
(the project method text is not in AGENTS.md, so `.po/methods/README.md` is the only pointer to
the methods). `.po/check.sh` does not run `change-record.py` or `proof.py`; only freshness was
asked for.

## Limits

Freshness only proves that paths cited in `docs/run.md` and the verify skill exist and that the
smoke commands exit 0; it does not prove the prose is true. Nothing yet requires a change record
per commit, because the AGENTS.md rule that says so was left out.
