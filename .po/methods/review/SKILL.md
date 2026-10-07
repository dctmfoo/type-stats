---
name: review
description: "Review your own change adversarially before reporting it, with one rubric and a pragmatic lead's verdict. Read when a task changes behavior or structure that later work will build on."
---

# Review

Review your own change as an adversarial reviewer would, then judge your findings as a pragmatic lead. One session, one pass: you are both the reviewer and the lead.

The deliverable is a verdict in the change record. Fix what lands in Act on before reporting; leave the rest as recorded findings for whoever assigned the task.

## Step 1, Determine Scope

Collect the task's changes: `git diff` of the uncommitted work, or `git diff <first task commit>^..HEAD` for committed units. Read the surrounding context files the change depends on: callers, callees, type definitions.

## Step 2, State the Intent

Write one paragraph of intent from the task's request, docs/brief.md's "Done means" and the code itself. If you cannot state it, the task is unclear: ask whoever assigned the task instead of guessing.

Review whether the code achieves this intent well. Do not question the intent itself.

## Step 3, Review

Go through every lens in [`references/rubric.md`](references/rubric.md) and the code-quality lens in [`references/code-quality-review.md`](references/code-quality-review.md) that is relevant. Do not force lenses that don't apply. A simple bug fix does not need paragraphs about architectural integrity.

For each finding, write:

1. **Severity**: `critical` (bugs, data loss, security issues, broken behavior) | `warning` (design or maintainability risk that will cause pain) | `nit` (style, naming, minor improvement).
2. **Location**: file:line or function name.
3. **Finding**: what the problem is, in concrete terms.
4. **Evidence**: why it is a problem. When you suspect a bug, trace the execution path that triggers it. Don't just flag "this could be nil".
5. **Suggestion** (optional): what to do instead, if you have a concrete alternative.

A good finding references specific code, explains why, and distinguishes "this is broken" from "I would have done this differently". An empty review is a valid outcome.

## Step 4, Lead Judgment

Now switch to the lead: a pragmatic senior engineer, not a neutral aggregator. Filter hard.

- **Nitpick gravity.** An adversarial pass fills its space. If every finding is a nit or a style preference, the code is probably fine. Say so.
- **Hypothetical vs. actual.** "What if someone passes null here?" is only a finding if a caller can actually pass null. Trace the call site; dismiss it if the input is validated upstream or the type system prevents it.
- **Premature abstraction.** Extracting functions, adding interfaces, creating abstractions: does this code need to change in a second way? If not, simple inline code beats the abstraction.
- **"I would have done it differently."** Not a bug and not actionable unless it shows a concrete problem with the current approach.
- **When the finding is right.** Don't dismiss a finding because it is uncomfortable. A concrete execution path, a gap in your own model of the code, or "...yeah, actually" means act. Correctness and security findings get more scrutiny before dismissal, not less.

Categorize every finding:

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. If this list has more than 5 items, you are not filtering hard enough.
- **Consider**. Legitimate points, but not clearly worth the cost right now. Worth the attention of whoever assigned the task.
- **Noted**. Technically valid but not actionable.
- **Dismissed**. Wrong, nitpicky, or missing context. Brief explanation why.

## Step 5, Act and Record

Fix every Act on finding, rerun the affected checks, and run `python3 .po/bin/proof.py prove` again before committing. Then write the verdict into the change record:

### Review
- **Intent:** the paragraph from Step 2.
- **Act on:** each finding, how it was fixed, and the check that proves it.
- **Consider:** each finding and the tradeoff.
- **Noted:** brief list.
- **Dismissed:** each finding with its reason. The dismissals let whoever assigned the task overrule your judgment where it disagrees.
