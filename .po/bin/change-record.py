#!/usr/bin/env python3
"""Check change records. Init copies this file into a project as .po/bin/change-record.py.

change-record.py [FILE ...]  check the named records, or every docs/changes/*.md

A record fills each section of .po/change.md. See that template for authoring guidance.
"""
from pathlib import Path
import re
import subprocess
import sys

SECTIONS = ('What changed', 'Checks', 'Methods used', 'Friction', 'Harness impact', 'Limits')
METHODS = Path(__file__).resolve().parent.parent / 'methods'


def body(text, heading):
    m = re.search(rf'^## {re.escape(heading)}[ \t]*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return None if m is None else m.group(1).strip()


def method(item):
    # "- tdd", "- `tdd`: why", "- **tdd** - why" or "- .po/methods/tdd/SKILL.md" all name tdd.
    m = re.search(r'methods/([a-z0-9-]+)', item) or re.search(r'[A-Za-z0-9][A-Za-z0-9-]*', item)
    return m.group(m.re.groups).lower() if m else ''


def problems(path):
    text = path.read_text()
    for heading in SECTIONS:
        content = body(text, heading)
        if content is None:
            yield f'no "## {heading}" section'
        elif not content or content.startswith('<'):
            yield f'"## {heading}" is not filled in'
    used = [method(line[2:]) for line in (body(text, 'Methods used') or '').splitlines() if line.startswith('- ')]
    known = sorted(p.parent.name for p in METHODS.glob('*/SKILL.md'))
    unknown = [name for name in used if name != 'none' and name not in known]
    if unknown:
        yield f'not in {METHODS.name}/: {", ".join(unknown)} (choose from {", ".join(known)}, or none)'


def main(argv):
    if argv[:1] in (['-h'], ['--help']):
        print((__doc__ or '').strip())
        return 0
    root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
    paths = [Path(a) for a in argv] or sorted(root.glob('docs/changes/*.md'))
    errors = [f'{path}: {p}' for path in paths for p in
              (problems(path) if path.is_file() else ['no such change record'])]
    for error in errors:
        print('change record: ' + error, file=sys.stderr)
    if not errors:
        print(f'PASS {len(paths)} change record(s).')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
