#!/usr/bin/env python3
"""Collect the evidence for a harness review. Init copies this file into a project as .po/bin/evidence.py.

evidence.py [--since COMMIT] [TRANSCRIPT.jsonl ...]

Prints counts, file paths, commit subjects and the names of methods. It never prints transcript text, record
text or file contents. The review starts at the commit that last changed .po/harness.json. With no
.po/harness.json, --since COMMIT sets the start, else it is the whole history; with one, --since is an error.
It reads recipes and records without running a smoke command. Judgment stays with the reviewer: this script
separates what can be counted from what must be read.
"""
import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
NOTES = ('docs/', '.po/', '.claude/', '.agents/', '.codex/', 'AGENTS.md', 'CLAUDE.md', 'README.md', '.gitignore', '.no-mistakes.yaml')
EDITS = ('Edit', 'Write', 'MultiEdit', 'NotebookEdit')
MAX_COMMITS = 200


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True).stdout


def commits(base):
    span = f'{base}..HEAD' if base else 'HEAD'
    print(f'## 2. commits since {base[:7] if base else "the start"} (at most {MAX_COMMITS})')
    for line in git('log', '--reverse', f'--max-count={MAX_COMMITS}', '--format=%h %cI %s', span).splitlines():
        files = git('show', '--name-only', '--format=', line.split()[0]).split()
        code = [f for f in files if not f.startswith(NOTES)]
        flags = {'run_recipe': 'docs/run.md' in files,
                 'skill': any(re.match(r'\.(claude|agents|codex)/skills/', f) for f in files),
                 'check': any(f == '.po/check.sh' for f in files),
                 'change_record': any(f.startswith('docs/changes/') for f in files)}
        print(f'{line[:100]}\n    code_files={len(code)} ' + ' '.join(f'{k}={v}' for k, v in flags.items()))


def recipes(fresh, files):
    print('\n## 3. recipes (static; smoke commands are not run)')
    names = {Path(f).name for f in files if not f.startswith('.po/methods/')}
    paths = [fresh.RUN] if fresh.RUN.is_file() else []
    paths += sorted(p for base in fresh.SKILLS for p in Path(base).glob('*/**/*.md'))
    missing = [e for p in paths for e in fresh.stale_paths(p, names)]
    print(f'recipe files={len(paths)} stale_citations={len(missing)}')
    for error in missing:
        print('  ' + error.split(', which')[0])
    if fresh.RUN.is_file():
        prose = fresh.split(fresh.RUN.read_text())[0]
        documented, ran, open_seams = fresh.seams(prose), fresh.driven(files, prose), fresh.uncovered(files)
        manual = [flag for _, flag, reason in fresh.manual() if reason and flag in documented]
        print(f'seams documented={len(documented)} driven_by_a_check={len(ran)} manual={len(manual)} uncovered={len(open_seams)}')
        for flag in open_seams:
            print('  uncovered seam ' + flag)
    hits = Counter((name, term) for name, _, term in fresh.retired(files))
    print(f'stale_terms listed={len(fresh.terms())} hits={sum(hits.values())}')
    for (name, term), n in sorted(hits.items()):
        print(f'  {name}: {term!r} x{n}')


def records(due, record, base):
    print(f'\n## 4. change records since {base[:7] if base else "the start"}')
    names = due.records_since(base)
    friction = harness = 0
    methods = Counter()
    rows = []
    for name in names:
        text = git('show', f'HEAD:{name}')
        felt = (record.body(text, 'Friction') or 'None.') != 'None.'
        touched = (record.body(text, 'Harness impact') or 'None.') != 'None.'
        used = sorted({record.method(line[2:]) for line in (record.body(text, 'Methods used') or '').splitlines()
                       if line.startswith('- ')} - {'none', ''})
        friction, harness = friction + felt, harness + touched
        methods.update(used)
        rows.append(f'  {name} friction={"yes" if felt else "no"} harness_impact={"yes" if touched else "no"} '
                    f'methods={",".join(used) or "none"}')
    print(f'records={len(names)} with_friction={friction} with_harness_impact={harness}')
    print('methods named: ' + (', '.join(f'{m} x{n}' for m, n in sorted(methods.items())) or 'none'))
    print('\n'.join(rows))
    print('Read the Friction and Harness impact sections of the records marked yes; this script does not quote them.')


def transcript(path):
    tools, results, order = Counter(), {}, []
    skipped = 0
    for line in path.read_text(errors='replace').splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            skipped += 1
            continue
        content = (row.get('message') or {}).get('content') if isinstance(row, dict) else None
        if not isinstance(content, list):
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get('type') == 'tool_result':
                body = item.get('content')
                text = body if isinstance(body, str) else ' '.join(x.get('text', '') for x in body or [] if isinstance(x, dict))
                results[item.get('tool_use_id')] = (text, bool(item.get('is_error')))
            elif item.get('type') == 'tool_use':
                order.append(item)
    skills = methods = web = denied = checks = failed = flaky = 0
    unchanged_failure = False
    for use in order:
        name, text = use.get('name', ''), json.dumps(use.get('input', {}))
        tools[name] += 1
        skills += name == 'Skill'
        reads = name in ('Read', 'Bash')
        skill_file = bool(re.search(r'\.(claude|agents|codex)/skills/[^"\s]*SKILL\.md', text))
        methods += reads and '.po/methods/' in text
        web += name in ('WebSearch', 'WebFetch') or 'web_search' in name
        result, error = results.get(use.get('id'), ('', False))
        denied += 'hook error' in result[:120]
        if name in EDITS:
            unchanged_failure = False
        if name == 'Bash' and '.po/check.sh' in text:
            checks += 1
            bad = error or 'FAIL' in result or 'No proof recorded' in result
            failed += bad
            flaky += bool(unchanged_failure and not bad)
            unchanged_failure = bool(bad)
        tools['_skill_file_reads'] += reads and skill_file
    return (f'{path.name[:8]} tools={sum(v for k, v in tools.items() if k[0] != "_")} Skill={skills} '
            f'skill_file_reads={tools["_skill_file_reads"]} method_reads={methods} web={web} check_runs={checks} '
            f'check_failed={failed} check_passed_after_failure_without_edit={flaky} hook_denials={denied} '
            f'unreadable_lines={skipped}')


def main(argv):
    ask = argparse.ArgumentParser(description='Collect the evidence for a harness review.')
    ask.add_argument('--since', help='first commit to exclude; only when .po/harness.json does not exist')
    ask.add_argument('transcripts', nargs='*', type=Path)
    args = ask.parse_args(argv)
    top = subprocess.run(['git', 'rev-parse', '--show-toplevel', 'HEAD'], capture_output=True, text=True)
    if top.returncode:
        print('evidence: run this inside a git repository with a commit.', file=sys.stderr)
        return 1
    os.chdir(top.stdout.splitlines()[0])
    sys.path.insert(0, str(HERE))
    fresh, due, record = load('freshness'), load('harness-due'), load('change-record')
    if args.since and due.MARKER.is_file():
        print(f'evidence: --since is only for a project with no {due.MARKER}; the marker sets the base.', file=sys.stderr)
        return 1
    try:
        base = args.since or due.marker()
    except ValueError as error:
        print(f'evidence: {error}', file=sys.stderr)
        return 1
    if base:
        base = subprocess.run(['git', 'rev-parse', '--verify', '-q', f'{base}^{{commit}}'], capture_output=True, text=True).stdout.strip()
        if not base:
            print(f'evidence: --since {args.since} is not a commit.', file=sys.stderr)
            return 1
    print('## 1. state')
    print(f'head={git("rev-parse", "--short", "HEAD").strip()} review_starts_after={base[:7] if base else "the start"}')
    print('harness-due: ' + subprocess.run([sys.executable, str(HERE / 'harness-due.py')], capture_output=True, text=True).stdout.strip())
    settings = Path('.claude/settings.json')
    memory_off = settings.is_file() and '"autoMemoryEnabled": false' in settings.read_text()
    print(f'.po/methods={Path(".po/methods").is_dir()} .po/change.md={Path(".po/change.md").is_file()} '
          f'docs/changes={Path("docs/changes").is_dir()} auto_memory_off={memory_off}')
    commits(base)
    recipes(fresh, fresh.project_files())
    records(due, record, base)
    print('\n## 5. transcripts (counts only)')
    status = 0
    for path in args.transcripts:
        if path.is_file():
            print(transcript(path))
        else:
            print(f'{path.name[:8]} unreadable')
            status = 1
    if not args.transcripts:
        print('none given; pass the project\'s session transcripts (.jsonl) to count tool use, check runs and skill reads')
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
