#!/usr/bin/env python3
"""Score an unchanged Genkit archive against the source actually tested by CI.

Pana verifies remote default-branch metadata, which cannot describe a repository
migration before it merges. Same-repository PRs use an isolated Git mirror of
GitHub's exact tested merge commit. Main and publishers use the public source.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPOSITORY = 'leehack/llamadart'
CLONE_URL = 'https://github.com/' + REPOSITORY
PUBSPEC = 'packages/genkit_llamadart/pubspec.yaml'
PACKAGE_URL = CLONE_URL + '/tree/main/packages/genkit_llamadart'
SCORE_COMMAND = ['dart', 'pub', 'global', 'run', 'pana', '.',
                 '--exit-code-threshold', '0']


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments])


def is_ancestor(root, ancestor, descendant):
    return subprocess.run(
        ['git', '-C', str(root), 'merge-base', '--is-ancestor', ancestor, descendant],
        stderr=subprocess.DEVNULL).returncode == 0


def candidate_commit(root, environment):
    """Only a matching same-repository PR merge may replace source lookup."""
    if environment.get('GITHUB_EVENT_NAME') != 'pull_request':
        return None
    event = json.loads(Path(environment['GITHUB_EVENT_PATH']).read_text())
    if (environment.get('GITHUB_REPOSITORY') != REPOSITORY
            or event['repository']['full_name'] != REPOSITORY
            or event['pull_request']['base']['repo']['full_name'] != REPOSITORY):
        raise ValueError('Candidate scoring requires this repository')
    pr = event['pull_request']
    if pr['head']['repo']['full_name'] != REPOSITORY:
        return None
    revisions = [environment.get('GITHUB_SHA', ''),
                 pr['base']['sha'], pr['head']['sha']]
    if not all(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha)
               and sha != '0' * 40 for sha in revisions):
        raise ValueError('Candidate scoring requires exact GitHub revisions')
    merge, base, head = revisions
    if git(root, 'rev-parse', 'HEAD').decode().strip() != merge:
        raise ValueError('Checkout differs from GitHub tested merge')
    if git(root, 'rev-parse', '--is-shallow-repository').decode().strip() != 'false':
        raise ValueError('Candidate source needs complete checkout; use fetch-depth: 0')
    parents = git(root, 'show', '-s', '--format=%P', merge).decode().split()
    # GitHub leaves pull_request.base.sha stale when the base branch advances
    # after the PR opens, so accept any first parent between it and the base tip.
    tip = 'refs/remotes/origin/' + str(pr['base']['ref'])
    if (len(parents) != 2 or parents[1] != head
            or not is_ancestor(root, base, parents[0])
            or not is_ancestor(root, parents[0], tip)):
        raise ValueError('Tested merge does not match GitHub PR base and head')
    return merge


def score(package, root, environment=None):
    package, root = Path(package).resolve(), Path(root).resolve()
    environment = dict(os.environ if environment is None else environment)
    revision = candidate_commit(root, environment)
    if revision is None:
        print('Pana source: public repository default branch', flush=True)
        return subprocess.run(SCORE_COMMAND, cwd=package,
                              env=environment).returncode
    metadata = package / 'pubspec.yaml'
    entry = git(root, 'ls-tree', revision, '--', PUBSPEC).decode().split()
    if len(entry) != 4 or entry[0] != '100644' or entry[1] != 'blob':
        raise ValueError('Candidate package manifest must be a regular Git blob')
    content = metadata.read_bytes()
    if metadata.is_symlink() or content != git(root, 'show', revision + ':' + PUBSPEC):
        raise ValueError('Staged manifest differs from tested candidate')
    if not re.search(rb'^repository: ' + re.escape(PACKAGE_URL.encode()) + rb'\r?$',
                     content, re.MULTILINE):
        print('Pana source: public repository (archive does not name monorepo)', flush=True)
        return subprocess.run(SCORE_COMMAND, cwd=package,
                              env=environment).returncode
    # The archive stays byte-for-byte unchanged. Only this child process's Git
    # source lookup for our repository uses the exact, publicly reviewed commit.
    with tempfile.TemporaryDirectory(prefix='genkit-pana-source-') as folder:
        mirror = Path(folder) / 'source.git'
        subprocess.run(['git', 'clone', '--bare', '--shared', '--quiet',
                        '--', str(root), str(mirror)], check=True)
        subprocess.run(['git', '--git-dir', str(mirror), 'update-ref',
                        'refs/heads/main', revision], check=True)
        subprocess.run(['git', '--git-dir', str(mirror), 'symbolic-ref',
                        'HEAD', 'refs/heads/main'], check=True)
        # Preserve other job-scoped Git settings without changing any config file.
        count = int(environment.get('GIT_CONFIG_COUNT', '0'))
        if count < 0:
            raise ValueError('Invalid Git configuration count')
        environment['GIT_CONFIG_COUNT'] = str(count + 1)
        environment[f'GIT_CONFIG_KEY_{count}'] = (
            'url.' + mirror.as_uri() + '.insteadOf')
        environment[f'GIT_CONFIG_VALUE_{count}'] = CLONE_URL
        print('Pana source: tested PR merge ' + revision
              + ' (isolated Git mirror; public URL checks unchanged)', flush=True)
        return subprocess.run(SCORE_COMMAND, cwd=package,
                              env=environment).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        return score(args.package, root)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit('Genkit package score verification failed: ' + str(error))


if __name__ == '__main__':
    raise SystemExit(main())
