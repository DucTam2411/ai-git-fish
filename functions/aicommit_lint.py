#!/usr/bin/env python3
"""Scan a staged git diff (read from stdin) for 'dump code' smells.

Flags hardcoded localhost / loopback / all-interfaces hosts left in production
code — the kind of throwaway default you write while wiring something up and
mean to swap for config/env before it ships. Prints "path:line<TAB>reason" per
hit to stdout and exits 1 when anything is found (0 if clean) so aicommit can
block the commit, mirroring the gitleaks gate.

Only ADDED lines are scanned. Docs, examples and test files are skipped — a
literal localhost there is legitimate, not a smell.
"""
import re
import sys

# Paths where a literal localhost is expected and shouldn't block a commit.
SKIP_FILE = re.compile(
    r'(\.(md|markdown|mdx|txt|rst)$'
    r'|\.(example|sample|dist|template)$'
    r'|(^|/)(tests?|__tests__|spec|specs|e2e|cypress|fixtures?|mocks?|__mocks__)/'
    r'|\.(test|spec|stories)\.[a-z0-9]+$'
    r'|(^|/)\.env)',
    re.IGNORECASE,
)

# Each: (regex over the added line, human reason). First match per line wins.
PATTERNS = [
    (re.compile(r'\blocalhost\b', re.IGNORECASE), 'hardcoded localhost'),
    (re.compile(r'(?<![\d.])127\.0\.0\.1(?![\d.])'), 'hardcoded loopback 127.0.0.1'),
    (re.compile(r'(?<![\d.])0\.0\.0\.0(?![\d.])'), 'hardcoded 0.0.0.0 (all interfaces)'),
    (re.compile(r'\[::1\]'), 'hardcoded IPv6 loopback [::1]'),
]


def scan(diff: str):
    """Yield (path, new_file_line, reason) for every smell in the diff."""
    path = None
    new_line = 0
    for line in diff.splitlines():
        if line.startswith('+++ '):
            p = line[4:].strip()
            if p.startswith('b/'):
                p = p[2:]
            path = None if p == '/dev/null' else p
        elif line.startswith('@@'):
            m = re.search(r'\+(\d+)', line)
            new_line = int(m.group(1)) if m else 0
        elif line.startswith('+'):
            content = line[1:]
            if path and not SKIP_FILE.search(path):
                for rx, reason in PATTERNS:
                    if rx.search(content):
                        yield (path, new_line, reason)
                        break
            new_line += 1
        elif line.startswith(' '):
            # context line advances the new-file counter; removed ('-') and
            # metadata ('diff --git', 'index', '\ No newline') lines do not.
            new_line += 1


def main() -> int:
    hits = list(scan(sys.stdin.read()))
    for path, ln, reason in hits:
        print(f'{path}:{ln}\t{reason}')
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
