#!/usr/bin/env python3
"""Say whether a harness review is due. Init copies this file into a project as .po/bin/harness-due.py.

harness-due.py       exit 0 when 5 or more change records were committed since the last review, 1 when
                     fewer, 2 when .po/harness.json cannot be read as a JSON object or no commit exists
harness-due.py mark  write .po/harness.json; commit it with the accepted review's changes

The last review is the commit that last changed .po/harness.json, so a squash or rebase merge keeps it.
The file holds {"commit": "<sha>", "date": "YYYY-MM-DD"}; it is rewritten by `mark` and not read for the
commit. With no committed marker every committed record counts. Work in progress does not count: a record
is committed or it is not evidence.
Run .po/bin/evidence.py to collect what a review reads.
"""
import argparse
from datetime import date
import json
import os
from pathlib import Path
import subprocess
import sys

MARKER = Path('.po/harness.json')
RECORDS = 'docs/changes'
THRESHOLD = 5


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True)


def marker():
    """The commit that last changed the marker file, None when there has been no review. Raises ValueError when unreadable."""
    if not MARKER.is_file():
        return None
    try:
        if not isinstance(json.loads(MARKER.read_text()), dict):
            raise ValueError
    except OSError as error:
        raise ValueError(f'{MARKER} cannot be read: {error.strerror}. Restore read access and try again.') from error
    except ValueError:
        raise ValueError(f'{MARKER} is not {{"commit": "<sha>", "date": "<day>"}}. Run `harness-due.py mark` to rewrite it.')
    return git('log', '-1', '--format=%H', '--', str(MARKER)).stdout.strip() or None


def records_since(commit):
    """Change records committed after the marker commit, or every committed record when there is none."""
    if commit is None:
        listed = git('ls-tree', '-r', '--name-only', 'HEAD', '--', RECORDS).stdout
    else:
        listed = git('log', '--diff-filter=A', '--name-only', '--format=', f'{commit}..HEAD', '--', RECORDS).stdout
    return sorted({name for name in listed.splitlines() if name.endswith('.md')})


def main(argv):
    ask = argparse.ArgumentParser(description='Say whether a harness review is due.')
    ask.add_argument('command', nargs='?', choices=['mark'])
    args = ask.parse_args(argv)
    top = git('rev-parse', '--show-toplevel')
    head = git('rev-parse', 'HEAD')
    if top.returncode or head.returncode:
        print('harness-due: run this inside a git repository with a commit.', file=sys.stderr)
        return 2
    os.chdir(top.stdout.strip())
    if args.command == 'mark':
        MARKER.parent.mkdir(exist_ok=True)
        MARKER.write_text(json.dumps({'commit': head.stdout.strip(), 'date': date.today().isoformat()}, indent=2) + '\n')
        print(f'harness-due: {MARKER} now marks {head.stdout.strip()[:7]}. Commit it with the review\'s changes.')
        return 0
    try:
        since = marker()
    except ValueError as error:
        print(f'harness-due: {error}', file=sys.stderr)
        return 2
    count = len(records_since(since))
    base = f'since {since[:7]}' if since else 'in all'
    due = count >= THRESHOLD
    print(f'{"due" if due else "not due"}: {count} change record(s) {base}; a review is due at {THRESHOLD}.')
    return 0 if due else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
