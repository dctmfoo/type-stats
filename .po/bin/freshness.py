#!/usr/bin/env python3
"""Check that the project's recipes still match its code. Init copies this file into a project as .po/bin/freshness.py.

freshness.py  check docs/run.md and Markdown under project skills in .claude/, .agents/ and .codex/

Fails on a cited file that is gone, a failing smoke command, a flag in the docs/run.md seam table that no
check drives (list one a person must confirm in .po/manual-seams.txt), and any term listed in
.po/stale-terms.txt that a project file still names.

See the "Fresh recipes" section of po-kit's README.md for authoring guidance and check limits.
"""
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys

RUN = Path('docs/run.md')
SKILLS = ('.claude/skills', '.agents/skills', '.codex/skills')
FENCE = re.compile(r'^[ \t]*(```+|~~~+)(.*)$')
SLASHED = re.compile(r'(?:\./)?[\w@+.-][\w@.+-]*(?:/[\w@.+-]+)*/?')
EXTENSION = re.compile(r'\.[A-Za-z][A-Za-z0-9]*$')
BARE = re.compile(r'[\w@+.-][\w@.+-]*\.(?:py|sh|ts|tsx|jsx|mjs|json|toml|ya?ml|swift|rs|go|rb|java|kt|cpp|html|css|md)')
DOMAIN = re.compile(r'[\w-]+\.(?:com|org|net|io|dev|ai|app)$')
SEAM = re.compile(r'^\|[ \t]*`(--[A-Za-z0-9][\w-]*)', re.M)
OUTSIDE = ('~', '/', '$HOME', '${HOME}')
MANUAL = Path('.po/manual-seams.txt')
STALE = Path('.po/stale-terms.txt')
# po-kit's own copies, change records (history may name what was retired) and scratch files are not scanned for retired terms.
HISTORY = ('.po/methods/', '.po/bin/', '.po/tmp/', 'docs/changes/')
LARGEST = 1_000_000
TIMEOUT = 120
RUNNING = 'PO_FRESHNESS_RUNNING'


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True)


def split(text):
    """The prose of a recipe, and the commands of its smoke blocks."""
    prose, smoke, fence = [], [], None
    for line in text.splitlines():
        found = FENCE.match(line)
        info = found.group(2).strip() if found else ''
        if found and fence is None and not (found.group(1)[0] == '`' and '`' in info):
            fence = (found.group(1), info.split()[0] if info else '')
        elif fence is not None and found and not info and found.group(1)[0] == fence[0][0] \
                and len(found.group(1)) >= len(fence[0]):
            fence = None
        elif fence is None:
            prose.append(line)
        elif fence[1] == 'smoke' and line.strip() and not line.lstrip().startswith('#'):
            smoke.append(line.strip())
    return '\n'.join(prose), smoke


def words(span):
    """The words of a code span to check, and the names of files the span places outside the repository.

    A span that starts with ~, / or $HOME is one location, because an unquoted path may hold spaces.
    Inside a command, a quoted word is one word and a word starting that way is outside too."""
    if span.lstrip().startswith(OUTSIDE):
        return [], [span.rstrip('/').rsplit('/', 1)[-1]]
    try:
        tokens = shlex.split(span)
    except ValueError:
        tokens = span.split()
    check, outside = [], []
    for token in tokens:
        if token.startswith(OUTSIDE) or re.search(r'\s', token):
            outside.append(token.rstrip('/').rsplit('/', 1)[-1])
            continue
        word = token.strip('\'"([,;').rstrip('\'")],;:.')
        if BARE.fullmatch(word) or (SLASHED.fullmatch(word) and '/' in word
                                    and not DOMAIN.match(word.split('/')[0])
                                    and (word.endswith('/') or EXTENSION.search(word))):
            check.append(word)
    return check, outside


def cited(prose):
    """Repository paths and file names the prose names in code spans, including inside commands.

    A bare name that the same prose also places outside the repository (`pause.json` beside
    `~/Library/App/pause.json`) names that outside file, so it is not a repository file to find."""
    found, outside = [], set()
    for span in re.findall(r'`([^`\n]+)`', prose):
        check, away = words(span)
        found += check
        outside.update(away)
    return [word for word in dict.fromkeys(found) if word not in outside]


def skill_root(path):
    return Path(*path.parts[:3]) if '/'.join(path.parts[:2]) in SKILLS and len(path.parts) > 3 else None


def ignored(rel):
    return rel.startswith('.po/tmp/') or git('check-ignore', '-q', '--', rel).returncode == 0


def exists(span, path, names):
    rel = span[2:] if span.startswith('./') else span
    if '/' not in rel.rstrip('/') and not rel.endswith('/'):
        return rel in names or ignored(rel)
    bases = [Path('.'), path.parent] + ([skill_root(path)] if skill_root(path) else [])
    return any((base / rel).exists() for base in bases) or ignored(rel)


def run_smoke(command):
    """Run one smoke command in its own session so a timeout can end everything it started."""
    child = subprocess.Popen(['sh', '-c', command], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             env={**os.environ, RUNNING: '1'}, start_new_session=True)
    try:
        out, err = child.communicate(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.communicate()
        raise
    return subprocess.CompletedProcess(child.args, child.returncode, out, err)


def stale_paths(path, names):
    prose = split(path.read_text())[0]
    for span in cited(prose):
        if not exists(span, path, names):
            yield f'{path}: cites `{span}`, which does not exist. Update the recipe or restore the file.'


def problems(path, names):
    yield from stale_paths(path, names)
    smoke = split(path.read_text())[1]
    for command in smoke:
        try:
            ran = run_smoke(command)
        except subprocess.TimeoutExpired:
            yield f'{path}: smoke command timed out after {TIMEOUT}s: {command}'
            continue
        if ran.returncode:
            tail = (ran.stderr.strip() or ran.stdout.strip()).splitlines()[-1:]
            yield f'{path}: smoke command failed (exit {ran.returncode}): {command}' + (f' -> {tail[0][:200]}' if tail else '')
    if path == RUN and not smoke:
        yield (f'{path}: has no smoke block. Add a ```smoke fenced block listing commands that run offline and '
               f'exit 0 while these instructions are true.')


def project_files():
    return [name for name in git('ls-files', '-co', '--exclude-standard').stdout.splitlines() if Path(name).is_file()]


def read(name):
    """Text of a project file, or None when it is binary or very large."""
    try:
        data = Path(name).read_bytes()
    except OSError:
        return None
    return None if len(data) > LARGEST or b'\0' in data else data.decode('utf-8', 'replace')


def seams(prose):
    """Flags the docs/run.md table documents: rows whose first cell is a `--flag` code span."""
    return list(dict.fromkeys(SEAM.findall(prose)))


def checks_text(files, prose):
    """What the project's checks say: .po/check.sh and scripts, tests and .po scripts, plus the smoke commands."""
    def check(name):
        top, *rest = Path(name).parts
        if top == '.po':
            return name.endswith(('.sh', '.py')) and rest[0] not in ('bin', 'methods', 'tmp')
        return top.lower() in ('scripts', 'test', 'tests') and not name.endswith(('.md', '.txt'))
    texts = [read(name) or '' for name in files if check(name)]
    return '\n'.join(texts + split(RUN.read_text())[1])


def manual():
    """(flag, reason) lines of .po/manual-seams.txt, with their line numbers."""
    rows = []
    for n, line in enumerate(MANUAL.read_text().splitlines() if MANUAL.is_file() else [], 1):
        if line.strip() and not line.lstrip().startswith('#'):
            flag, _, reason = line.strip().partition(' ')
            rows.append((n, flag, reason.strip()))
    return rows


def driven(files, prose):
    """Documented seams that a check or smoke command runs: a longer flag with the same start does not count."""
    text = checks_text(files, prose)
    return [flag for flag in seams(prose) if re.search(rf'(?<![\w-]){re.escape(flag)}(?![\w-])', text)]


def uncovered(files):
    """Documented seams that no check drives and no manual entry accepts."""
    prose = split(RUN.read_text())[0]
    ran = driven(files, prose)
    accepted = {flag for _, flag, reason in manual() if reason}
    return [flag for flag in seams(prose) if flag not in ran and flag not in accepted]


def coverage(files):
    if not RUN.is_file():
        return
    documented = seams(split(RUN.read_text())[0])
    for flag in uncovered(files):
        yield (f'{RUN}: seam `{flag}` is in the table but no check drives it. Add a check or smoke command '
               f'that runs it, or list it in {MANUAL} as "{flag} <why a person must confirm it>".')
    for n, flag, reason in manual():
        if flag not in documented:
            yield f'{MANUAL}:{n}: lists `{flag}`, which is not in the {RUN} seam table. Remove the line.'
        elif not reason:
            yield f'{MANUAL}:{n}: say why `{flag}` cannot be driven by a check.'


def terms():
    return [line.strip() for line in STALE.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')] if STALE.is_file() else []


def retired(files):
    """(file, line number, term) for every listed term a project file still names."""
    listed = terms()
    for name in files if listed else []:
        if name == str(STALE) or name.startswith(HISTORY):
            continue
        for n, line in enumerate((read(name) or '').splitlines(), 1):
            for term in listed:
                if term in line:
                    yield name, n, term


def stale_terms(files):
    for name, n, term in retired(files):
        yield (f'{name}:{n}: names retired term "{term}" (listed in {STALE}). Update the text, or remove the '
               f'term once nothing should name it.')


def main(argv):
    if argv[:1] in (['-h'], ['--help']):
        print((__doc__ or '').strip())
        return 0
    if os.environ.get(RUNNING):
        print('SKIP freshness check is already running; a smoke command must not call it again.')
        return 0
    top = git('rev-parse', '--show-toplevel')
    if top.returncode:
        print('freshness: run this inside the project\'s git repository.', file=sys.stderr)
        return 1
    root = Path(top.stdout.strip())
    os.chdir(root)
    files = project_files()
    names = {Path(name).name for name in files if not name.startswith('.po/methods/')}
    recipes = [RUN] if RUN.is_file() else []
    recipes += sorted(p for base in SKILLS for p in Path(base).glob('*/**/*.md'))
    errors = [] if RUN.is_file() else [f'{RUN}: is missing. Write the commands that install, run and test the product.']
    errors += [error for path in recipes for error in problems(path, names)]
    errors += list(coverage(files)) + list(stale_terms(files))
    for error in errors:
        print('freshness: ' + error, file=sys.stderr)
    if not errors:
        print(f'PASS {len(recipes)} recipe file(s) match the code.')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
