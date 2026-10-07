# Method library

Methods to read before building a change. Pick the ones the change needs from the table
below. Read `<name>/SKILL.md`, and every principle or reference it links, before building.
List each method you read under `## Methods used` in the change record;
`python3 .po/bin/change-record.py` checks that every name there is one of these.

| Name | Read it when the change |
|---|---|
| architect | adds a module, boundary, schema, stored state or other structure, or asks for a design only |
| tdd | fixes a bug, or adds behavior with a cheap local test target |
| blast-radius | changes code other parts depend on, or its brief asserts something about existing code |
| create-verification-skill | sets up or replaces the project's verify skill |
| maintain-verification-skill | refreshes the verify skill and feature map after the app changed |
| review | changes behavior or structure that later work will build on |

These files are plain Markdown, not registered skills, so any agent can read them.
`principles/` holds only the principles the methods above link to. po-kit's init copies this
folder, except `vendor.json`, into a project as `.po/methods/` and replaces it on reinstall;
change methods in po-kit.

## Source

Copied from [pstack-claude](https://github.com/michael-denyer/pstack-claude), Michael Denyer's
Claude Code port of Lauren Tan's pstack, at one pinned commit. po-kit's `library/vendor.json`
records the repository, commit and every file with its upstream source, and states each trim.
The trims remove pull requests, CLAUDE.md, subagent and multi-model fan-out and the model sheet;
outputs go to docs/, the change record and the prove command instead. The MIT licence is in
`LICENSE`.

No copy updates itself. In po-kit, `python3 scripts/pstack-upstream.py` prints how
pstack-claude's current main differs from the pinned commit for these files, so a person can
review and approve a new pin. CI runs it as information only.
