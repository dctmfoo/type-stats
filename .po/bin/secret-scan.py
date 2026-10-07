#!/usr/bin/env python3
"""Local common credential-format check; print filenames, never values."""
import os
from pathlib import Path
import re
import subprocess
import sys

patterns = [rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b', rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b',
            rb'\bsk-(?:ant-)?[A-Za-z0-9_-]{32,}\b']
names = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z']).split(b'\0')
bad = []
for raw in set(names):
    if not raw:
        continue
    p = Path(os.fsdecode(raw))
    if p.is_file() and not p.is_symlink() and any(re.search(pattern, p.read_bytes()) for pattern in patterns):
        bad.append(str(p))
if bad:
    print('FAIL possible secret in: ' + ', '.join(sorted(bad)), file=sys.stderr)
    sys.exit(1)
print('PASS common secret formats scan. This is not a complete credential audit.')
