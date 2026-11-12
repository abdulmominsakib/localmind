#!/usr/bin/env python3
"""Small same-run Web artifact guard and preview selector; never builds/deploys."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile

from select_jobs import inventory, select


def preview_action(event, paths):
    pr = event['pull_request']
    if (pr['head']['repo']['full_name'] != event['repository']['full_name']
            or pr['user']['login'] == 'dependabot[bot]'):
        return 'skip'
    if (event['action'] in ('labeled', 'unlabeled')
            and event.get('label', {}).get('name') != 'preview'):
        return 'skip'
    if event['action'] == 'closed':
        return 'cleanup'
    if any(label['name'] == 'preview' for label in pr['labels']):
        return 'build'
    if pr['draft']:
        return 'skip'
    return 'build' if select(paths)['jobs']['web-chat-contract'] else 'skip'


def verify_artifact(metadata, *, artifact_id, digest, run_id, sha, repository_id):
    """Bind the archive to GitHub's same-run immutable artifact identity."""
    origin = metadata.get('workflow_run', {})
    if (metadata.get('id') != artifact_id or metadata.get('expired') is not False
            or metadata.get('digest') != 'sha256:' + digest
            or origin.get('id') != run_id or origin.get('head_sha') != sha
            or origin.get('head_branch') != 'main'
            or origin.get('repository_id') != repository_id
            or origin.get('head_repository_id') != repository_id
            or not re.fullmatch(r'[0-9a-f]{64}', digest)):
        raise ValueError('Artifact is missing, expired, or has mismatched run/source/digest')


def extract_artifact(archive, destination, digest):
    """Fail closed on digest mismatch and unsafe ZIP entries before extraction."""
    with open(archive, 'rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != digest:
        raise ValueError('Artifact archive digest mismatch')
    with zipfile.ZipFile(archive) as bundle:
        names = set()
        for item in bundle.infolist():
            # ZipInfo.filename has already normalized Windows separators and
            # truncated NULs, so validate the original ZIP header name.
            name = item.orig_filename
            path = PurePosixPath(name)
            if (str(path) in names or path.is_absolute()
                    or '..' in path.parts or '\\' in name
                    or not path.parts or ':' in name
                    or str(path) != name.rstrip('/')
                    or re.search(r'[\x00-\x1f\x7f]', name)
                    or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError('Unsafe or duplicate artifact archive entry')
            names.add(str(path))
        if Path(destination).exists():
            raise ValueError('Artifact destination must be fresh')
        bundle.extractall(destination)


def verify_build(directory, sha, tree, flutter_version):
    metadata = json.loads((Path(directory) / 'llamadart-build.json').read_text())
    expected = {'commit': sha, 'tree': tree, 'base_href': '/',
                'target': 'lib/main.dart', 'flutter_version': flutter_version}
    if any(metadata.get(key) != value for key, value in expected.items()):
        raise ValueError('Artifact source or production build configuration mismatch')
    if '<base href="/">' not in (Path(directory) / 'index.html').read_text():
        raise ValueError('Artifact index is not built for the production root')


def main():
    if sys.argv[1:] == ['preview']:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        pr = event['pull_request']
        paths = []
        if (event['action'] != 'closed' and not pr['draft']
                and pr['head']['repo']['full_name'] == event['repository']['full_name']
                and not any(label['name'] == 'preview' for label in pr['labels'])):
            base, head = pr['base']['sha'], pr['head']['sha']
            if not all(re.fullmatch(r'[0-9a-f]{40}', sha) for sha in (base, head)):
                raise ValueError('Invalid preview source revision')
            paths = inventory(subprocess.check_output(
                ['git', 'diff', '--name-status', '-z', '--find-renames', f'{base}...{head}']))
        action = preview_action(event, paths)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('action=' + action + '\n')
        return
    if sys.argv[1:] != ['verify']:
        raise ValueError('Expected preview or verify')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if (os.environ['GITHUB_EVENT_NAME'] not in ('workflow_dispatch', 'push')
            or os.environ['GITHUB_REF'] != 'refs/heads/main'
            or event['repository']['full_name'] != 'leehack/llamadart'
            or os.environ['GITHUB_REPOSITORY'] != 'leehack/llamadart'
            or event['repository'].get('fork') is not False):
        raise ValueError('Production deployment requires a push to or a manual run on '
                         'this repository main')
    digest = os.environ['ARTIFACT_DIGEST']
    sha = os.environ['GITHUB_SHA']
    verify_artifact(json.loads(Path('web-artifact.json').read_text()),
                    artifact_id=int(os.environ['ARTIFACT_ID']), digest=digest,
                    run_id=int(os.environ['GITHUB_RUN_ID']), sha=sha,
                    repository_id=int(os.environ['GITHUB_REPOSITORY_ID']))
    tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True).strip()
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != sha:
        raise ValueError('Deployment checkout differs from the tested source')
    extract_artifact('web-artifact.zip', 'web-artifact', digest)
    verify_build('web-artifact', sha, tree, Path('.flutter-version').read_text().strip())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        raise SystemExit(f'Web artifact validation failed: {error}')
