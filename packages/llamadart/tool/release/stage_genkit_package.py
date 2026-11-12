#!/usr/bin/env python3
"""Stage the independent package outside ancestor archive exclusions.

Like the Apple companion publishers, publish a standalone copy: pub applies
ancestor .pubignore rules even when invoked inside a nested package.
"""
import argparse
from pathlib import Path
import shutil

EXCLUDED = {'.git', '.github', '.dart_tool', 'build', 'coverage',
            'pubspec.lock', 'pubspec_overrides.yaml', '__pycache__'}


def stage(source, destination):
    """Copy publishable source into a new directory, refusing symlink escapes."""
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination == source or source in destination.parents:
        raise ValueError('Destination must be outside the source package')
    # An existing target may contain someone else's work. Never replace it.
    if destination.exists():
        raise ValueError('Destination already exists; choose a new directory')
    files = []
    for path in source.rglob('*'):
        relative = path.relative_to(source)
        if any(part in EXCLUDED for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f'Package contains a symlink: {relative}')
        if path.is_file() and not path.name.endswith(('.log', '.profraw', '.pyc')):
            files.append((path, relative))
    for name in ('pubspec.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE'):
        if not (source / name).is_file():
            raise ValueError(f'Missing package file: {name}')
    destination.mkdir(parents=True)
    for path, relative in files:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination')
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2] / 'packages/genkit_llamadart'
    print(stage(source, args.destination))
