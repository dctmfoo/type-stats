#!/usr/bin/env python3
"""Exact working-tree proof. Init copies this file into a project as .po/bin/proof.py.

prove        run sh .po/check.sh and record the result in .po/proof.json
check        say whether .po/proof.json is a passing receipt for exactly the current files
fingerprint  print the fingerprint a receipt records

Nothing here blocks a commit. Any agent or person runs these as plain commands.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

RECEIPT = Path('.po/proof.json')
CHECKS = ['sh', '.po/check.sh']


def git(*args):
    return subprocess.check_output(['git', *args])


def paperwork(name):
    # Exclude notes and the receipt itself; docs/run.md supplies executable checks.
    return (name in ('AGENTS.md', 'CLAUDE.md', 'README.md', str(RECEIPT))
            or (name.startswith('docs/') and name.endswith('.md') and name != 'docs/run.md'))


def fingerprint():
    # Read actual bytes rather than a diff from HEAD. A receipt still matches
    # after committing, and staged/unstaged differences cannot hide a change.
    names = set(git('ls-files', '-z').split(b'\0'))
    names.update(git('ls-files', '-o', '--exclude-standard', '-z').split(b'\0'))
    h = hashlib.sha256()
    for raw in sorted(names):
        name = os.fsdecode(raw)
        if not name or paperwork(name):
            continue
        p = Path(name)
        # A removed index entry is not part of the current file tree. Skipping
        # it keeps proof stable when a tested deletion/rename is then staged.
        if not p.exists() and not p.is_symlink():
            continue
        h.update(raw + b'\0')
        if p.is_symlink():
            data, mode = os.fsencode(os.readlink(p)), b'link'
        elif p.is_file():
            data = p.read_bytes()
            mode = b'exec' if p.stat().st_mode & 0o111 else b'file'
        else:
            data, mode = b'', b'deleted'
        h.update(mode + b'\0' + str(len(data)).encode() + b'\0' + data)
    return h.hexdigest()


def receipt_problem():
    """Why .po/proof.json is not a passing receipt for the current files, or None when it is."""
    if not RECEIPT.is_file():
        return 'no proof has been recorded yet'
    try:
        receipt = json.loads(RECEIPT.read_text())
    except ValueError:
        return f'{RECEIPT} is not a readable receipt'
    if receipt.get('result') != 'pass':
        return 'the last prove did not pass'
    if receipt.get('fingerprint') != fingerprint():
        return 'the files changed after the last passing prove'
    return None


def prove():
    if not Path(CHECKS[1]).is_file():
        return f'po-kit: {CHECKS[1]} is missing, so there is nothing to prove.'
    # Invalidate an earlier receipt before rerunning checks. A later failed
    # check must never leave an old passing receipt usable.
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps({'result': 'checking'}))
    before = fingerprint()
    ran = subprocess.run(CHECKS, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(ran.stdout, end='')
    if ran.returncode != 0:
        RECEIPT.write_text(json.dumps({'result': 'fail'}))
        return f'po-kit: checks FAILED (exit {ran.returncode}). No proof recorded.'
    if fingerprint() != before:
        RECEIPT.write_text(json.dumps({'result': 'fail'}))
        return 'po-kit: the checks changed the code or the checks. No proof recorded. Prove again on stable files.'
    RECEIPT.write_text(json.dumps({'result': 'pass', 'command': CHECKS, 'fingerprint': before,
                                   'at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
                                   'output': ran.stdout[-2000:]}, indent=2) + '\n')
    print(f'po-kit: checks passed. Proof recorded in {RECEIPT}.')
    return None


def main(argv):
    if argv not in (['prove'], ['check'], ['fingerprint']):
        print((__doc__ or '').strip(), file=sys.stderr)
        return 2
    os.chdir(git('rev-parse', '--show-toplevel').decode().strip())
    if argv == ['fingerprint']:
        print(fingerprint())
        return 0
    if argv == ['prove']:
        problem = prove()
    else:
        problem = receipt_problem()
        problem = problem and f'po-kit: {problem}. The receipt does not prove these files.'
        if not problem:
            print(f'po-kit: {RECEIPT} is a passing receipt for exactly these files.')
    if problem:
        print(problem, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
