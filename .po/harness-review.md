# Harness review: <project>

You review how this project's agent harness performed, from evidence, and write one report. The harness is
`AGENTS.md`, `docs/run.md`, the project skills, `.po/check.sh`, the scripts it runs, and the method library.
You do not edit any of them, open a pull request or write `AGENTS.md`. A change you propose is built later, as an
ordinary change, by whoever the report goes to.

## Why this review ran

<The trigger: `harness-due.py` output, the date, or the friction that repeated. Name the commit the review starts after.>

## Evidence

Run these from the project root. Cite counts, file paths and commits; never copy transcript text or record text
into the report.

1. `python3 .po/bin/harness-due.py` for the trigger, and `python3 .po/bin/evidence.py [TRANSCRIPT.jsonl ...]` for
   commits, recipe freshness, seam coverage, retired terms, change-record counts and transcript counts.
   Before the first marker, consult `python3 .po/bin/evidence.py --help` to choose a narrower review base.
   <Transcripts to count, one path per line, if any are kept.>
2. Read the Friction and Harness impact sections of the records the script marks `yes`, and the checks' own output.
3. <Records the coordinator adds: task reports, blocked lines, recoveries for this project. Remove this line if none.>

Judgment is yours. The script counts check failures; you decide which were flakes (the same files passing on a
rerun) and which were defects, and say how you decided.

## What to look for

- The same friction in two or more changes, with the files it touched.
- Recipes, skills or check scripts that went stale: the freshness output, and anything it cannot see (a command that
  still runs but means something else; a feature no recipe mentions).
- Methods the work needed but never read, and instructions every agent read and ignored.
- Checks that failed for the wrong reason, or never failed when the behavior broke.
- Anything the harness carries that no change used. Removal is a candidate too.

## Candidates

Each candidate is one row, ranked: the change, the asset it touches, the evidence (counts, paths, commits), the
proof that it helps, and who decides.

| # | Change | Asset | Evidence | Proof | Decides |
|---|---|---|---|---|---|

Proof is a case built from the real failure, run with and without the change, passing at least two of three runs,
with graders written as code first. A change to the check needs a mutant that fails it. Write "unproven" with the
reason when you could not run the case; do not argue a candidate in.

Who decides: project skills, scripts, the check command and fact corrections in `docs/run.md` go to the
coordinator to promote. `AGENTS.md` additions, third-party tools and anything in `.po/bin/` or `.po/methods/`
(those come from po-kit and change upstream) go to the owner.

## Report

Write these sections, in order: **Conclusion** (three sentences at most), **Findings** (each with its evidence),
**Candidates** (the table above), **Considered and not proposed**, **Feedback for po-kit and the coordinator**,
**Limits** (what one pass and these counts cannot show). Say plainly what you did not measure.

## When done

If the owner accepted a review, run `python3 .po/bin/harness-due.py mark` and commit `.po/harness.json` with the
change that acts on it, so the next review starts there.
