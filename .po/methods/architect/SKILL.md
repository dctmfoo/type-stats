---
name: architect
description: "Sketch types, signatures, and module structure before code, then stay in the loop while implementation fills in. Read when a task adds a module, boundary, schema, stored state or other structure, or asks for a design only."
---

# Architect

Design before implementing. Sketch types, function signatures, class shapes, and module boundaries with `not implemented` bodies and pseudocode. Compare at least two shapes, then fill in code against the chosen sketch. If implementation proves the sketch wrong, throw it out and redesign.

## Start

Open a todolist with one entry per phase before starting.

1. Ground
2. Sketch
3. Agree
4. Implement
5. Scrap

## Phase A: Ground the problem

Build a real mental model of every system the new code touches. Read the code the change touches and its callers, and trace how data enters, moves and is stored, from the entry point to the end state.

Naming a file isn't grounding. Write down the traced path with real file and line references. If the design redefines ownership or layering, also read the git history of the existing shape (`git log -p` on the files involved) so its rationale becomes a constraint, not a guess.

Skip Phase A only when the work is genuinely greenfield with no surrounding system to integrate.

## Phase B: Sketch

Design it twice. Sketch at least two structurally distinct candidates yourself, each shaped per [`references/rationale-template.md`](references/rationale-template.md), before choosing, even when the first looks sufficient. This is the [exhaust-the-design-space](../principles/exhaust-the-design-space.md) principle made concrete. Whole-shape alternatives, not point fixes inside one shape. Sketch each candidate as if it were the only one; converging on a safe-looking middle defeats the exploration.

Apply this discipline to every candidate:

- Caller's usage first. Write the README-style usage and two or three real call sites before the types, then derive the type sketch from them. The usage is the spec. The two must agree, so reconcile the sketch to the usage, not the reverse.
- Data structures first. Get the core types right and the code becomes obvious. Trace each dominant access pattern through the proposed structure. If the answer is "we'll add a map / index / cache later," the structure is wrong.
- Interface depth. Compare the capability hidden behind the public surface relative to the size of that surface. Prefer a simple interface that pulls complexity into the callee, even when the implementation becomes less simple. Do not put transport or wire types on the public API. Parse into domain types behind the interface.
- Shared state: if two actors might both write, ask "what happens?" If the answer isn't "nothing," default to per-actor state with a merge at the read boundary, per [separate-before-serializing-shared-state](../principles/separate-before-serializing-shared-state.md).
- Make boundaries visible. `not implemented` errors for bodies, `// TODO` pseudocode for tricky logic, doc comments stating intent and invariants. A reader should trace data from input to output by reading types and signatures alone.
- Encode invariants in types: hard-to-misuse types > runtime checks > prose comments, per [encode-lessons-in-structure](../principles/encode-lessons-in-structure.md).
- Validate at boundaries, trust types inside, per [boundary-discipline](../principles/boundary-discipline.md). Business logic as pure functions. The shell stays thin.
- Single source of truth per invariant. Derive instead of sync.
- Idempotent state transitions where applicable, per [make-operations-idempotent](../principles/make-operations-idempotent.md). Ask what happens if the operation runs twice or crashes halfway.
- Short call chains. If tracing the flow needs more than three files, flatten the hierarchy, per [laziness-protocol](../principles/laziness-protocol.md) and [minimize-reader-load](../principles/minimize-reader-load.md).

Screen every candidate against [`references/design-red-flags.md`](references/design-red-flags.md) before choosing. Assume the next contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Prefer the design where a change that looks right from one file is right for the whole repo.

Compare viable candidates on interface depth. Prefer the design that hides more complexity behind a smaller, simpler public surface. A rich interface can keep call chains short by concentrating capability instead of scattering it across layers.

Pick one candidate as the base and graft the best parts of the others. Record the choice in the rationale's "Synthesis decision" section, and the losing shapes in "Alternatives considered".

## Phase C: Agree

Stop here when the task is design-only or its Build notes ask for a checkpoint. Write the rationale to the path the task names (default `docs/architecture/NN-topic.md`), report, and build nothing. Whoever assigned the task judges the design and settles any product question.

Otherwise proceed to implementation with the chosen design. For adversarial pressure on the design before implementing, apply the [review](../review/SKILL.md) skill's rubric to the sketch.

If whoever assigned the task pushes back on the shape, treat that as Phase A evidence. Re-ground and re-run Phase B before writing more code.

## Phase D: Implement against the sketch

Replace `not implemented` bodies with code, pseudocode with logic. The chosen sketch is the contract. Each unit ends green: its behavior checks pass and the proof tool records it before the commit.

Deviations from the sketch are signal worth surfacing, not friction to absorb silently. If a function needs a parameter the sketch didn't anticipate, ask whether the sketch was wrong, the requirement was missed, or the implementation is overreaching.

Before closing each implementation unit, compare accepted deviations with the saved behavior contracts, interfaces, and responsibility assignments. Update the affected parts of the existing sketch and rationale, and record why in its "Implementation reconciliation" section. A change from raising an error to returning a refusal must update the outcome contract before the next unit begins.

For a local deviation that leaves the shared contract intact, record the decision and why the design still holds; a local variable rename need not rewrite the architecture. Keep unresolved disagreements visible in the change record. Do not edit the specification merely to justify what was implemented. Use the existing design file rather than a parallel record per unit. Repeated structural deviations still trigger Phase E.

## Phase E: Scrap when the architecture is wrong

If implementation keeps producing friction the sketch can't absorb, throw the sketch out. Don't bolt fixes onto a wrong design, per [redesign-from-first-principles](../principles/redesign-from-first-principles.md) and [fix-root-causes](../principles/fix-root-causes.md).

The signal is a *pattern*, not single instances. Tells:

- The same shape of workaround appearing repeatedly across unrelated code.
- Multiple unrelated edge cases that all need special-case branches.
- Types that need escape hatches (`any`, casts, optional fields always set in practice) to compile.
- The "we need a lock" reflex when the sketch said the state wasn't shared.
- Callers having to know the abstraction's internal rules to use it.
- Two or more independent Phase D deviations of the same shape across the implementation.

Use judgment. A few edge cases don't condemn an architecture. Some problems are legitimately complex. Complexity in the data is not complexity in the design.

When you scrap:

1. Re-run Phase A over what's been built.
2. Redesign as if the new constraints had been day-one assumptions, per redesign-from-first-principles.
3. Subtract before adding, per [subtract-before-you-add](../principles/subtract-before-you-add.md). The new sketch should be smaller than the old one before it grows.
4. Return to Phase B.

## Outputs

The caller's usage is written first and the type sketch derived from it, per [foundational-thinking](../principles/foundational-thinking.md). One file with new types and signatures for small changes. Module map plus type definitions for larger work. The rationale goes to `docs/architecture/NN-topic.md` (or the path the task names), shaped per `references/rationale-template.md`, including the usage sketch and the synthesis decision. The change record links it.
