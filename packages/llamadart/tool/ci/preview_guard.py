#!/usr/bin/env python3
"""Trusted PR preview mutations, with live-state checks before every write."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from hf_space_deploy import Budget, status_of, with_retry
from select_jobs import inventory
from web_deployment import extract_artifact, preview_action, verify_build


class Superseded(Exception):
    """The event no longer describes the live PR; no further writes are safe."""


def gh_json(path):
    # gh keeps credentials and redirect URLs out of our output and argv.
    return json.loads(subprocess.check_output(['gh', 'api', path]))


def live_action(event, live, paths):
    """Close/reopen and same-head events are checked against current eligibility."""
    original = event['pull_request']
    if (live['number'] != original['number']
            or live['head']['sha'] != original['head']['sha']
            or live['head']['repo']['full_name'] != event['repository']['full_name']
            or live['base']['repo']['full_name'] != event['repository']['full_name']
            or live['base']['ref'] != 'main'):
        return 'skip'
    if event['action'] == 'closed':
        # A delayed close must not delete a reopened (or subsequently reclosed) PR.
        return ('cleanup' if live['state'] == 'closed' and live['closed_at']
                and live['closed_at'] == original['closed_at'] else 'skip')
    if live['state'] != 'open':
        return 'skip'
    return preview_action({**event, 'action': 'synchronize', 'pull_request': live}, paths)


def verify_preview_artifact(metadata, *, artifact_id, digest, run_id,
                            sha, repository_id, pr_number):
    """PR artifacts have their own boundary; production still requires main."""
    origin = metadata.get('workflow_run', {})
    name = metadata.get('name')
    valid_name = (type(pr_number) is int and pr_number > 0
                  and isinstance(name, str)
                  and re.fullmatch(rf'chat-app-preview-{pr_number}-[1-9][0-9]*', name))
    if (metadata.get('id') != artifact_id or not valid_name
            or metadata.get('expired') is not False
            or metadata.get('digest') != 'sha256:' + digest
            or origin.get('id') != run_id or origin.get('head_sha') != sha
            or origin.get('repository_id') != repository_id
            or origin.get('head_repository_id') != repository_id
            or not re.fullmatch(r'[0-9a-f]{64}', digest)):
        raise ValueError('Preview artifact run/source/digest mismatch')


class OperationFailed(Exception):
    """A provider operation failed; carries only a safe name and HTTP status."""

    def __init__(self, operation, status):
        super().__init__(operation, status)
        self.operation, self.status = operation, status

    def __str__(self):
        status = f'HTTP {self.status}' if isinstance(self.status, int) else 'no HTTP status'
        return f'Preview operation {self.operation} failed ({status}); no further writes attempted.'


def run_operation(operation, call, budget, before=None):
    in_provider_call = False

    def attempt():
        nonlocal in_provider_call
        in_provider_call = False
        if before:
            before()
        in_provider_call = True
        return call()

    try:
        return with_retry(operation, budget=budget, call=attempt)
    except Exception as error:
        if not in_provider_call:
            raise
        status = status_of(error)
        raise OperationFailed(operation, status if isinstance(status, int) else None) from None


class Preview:
    def __init__(self, event, read=gh_json):
        self.event, self.read = event, read
        self.repository = event['repository']['full_name']
        self.number = event['pull_request']['number']
        self.sha = event['pull_request']['head']['sha']
        if (self.repository != 'leehack/llamadart'
                or os.environ['GITHUB_REPOSITORY'] != self.repository
                or os.environ['GITHUB_EVENT_NAME'] != 'pull_request'
                or type(self.number) is not int or self.number <= 0
                or not re.fullmatch(r'[0-9a-f]{40}', self.sha)):
            raise ValueError('Invalid preview event repository or source')
        self.path = f'repos/{self.repository}/pulls/{self.number}'

    def guard(self, action):
        live = self.read(self.path)
        paths = []
        if (action == 'build' and live['state'] == 'open'
                and live['head']['sha'] == self.sha):
            base = live['base']['sha']
            if not re.fullmatch(r'[0-9a-f]{40}', base):
                raise ValueError('Invalid live base revision')
            # Fetch only data; no PR-provided helper is executed in this job.
            subprocess.check_call(['git', 'fetch', '--quiet', '--no-tags', 'origin', base, self.sha])
            paths = inventory(subprocess.check_output(
                ['git', 'diff', '--name-status', '-z', '--find-renames', f'{base}...{self.sha}']))
            live = self.read(self.path)
            if live['base']['sha'] != base:
                raise Superseded()
        if live_action(self.event, live, paths) != action:
            raise Superseded()

    def artifact(self):
        artifact_id = int(os.environ['ARTIFACT_ID'])
        digest = os.environ['ARTIFACT_DIGEST']
        metadata = self.read(f'repos/{self.repository}/actions/artifacts/{artifact_id}')
        verify_preview_artifact(
            metadata, artifact_id=artifact_id, digest=digest,
            run_id=int(os.environ['GITHUB_RUN_ID']), sha=self.sha,
            repository_id=int(os.environ['GITHUB_REPOSITORY_ID']),
            pr_number=self.number)
        with open('preview-artifact.zip', 'wb') as archive:
            subprocess.check_call(['gh', 'api',
                                   f'repos/{self.repository}/actions/artifacts/{artifact_id}/zip'],
                                  stdout=archive)
        extract_artifact('preview-artifact.zip', 'preview-artifact', digest)
        tree = subprocess.check_output(['git', 'rev-parse', self.sha + '^{tree}'], text=True).strip()
        flutter = subprocess.check_output(['git', 'show', self.sha + ':.flutter-version'], text=True).strip()
        verify_build('preview-artifact', self.sha, tree, flutter)
        subprocess.check_call(['bash', 'scripts/validate_chat_app_web_build.sh', 'preview-artifact'])

    def mutate(self, action, api, space, folder):
        if action == 'build':
            budget = Budget()
            # Each rate-limit retry rechecks state, including the upload after create.
            recheck = lambda: self.guard(action)
            try:
                info = run_operation('repo_info', lambda: api.repo_info(
                    repo_id=space, repo_type='space'), budget)
            except OperationFailed as error:
                if error.status != 404:
                    raise
                info = None
            if info is None:
                run_operation('create_repo', lambda: api.create_repo(
                    repo_id=space, repo_type='space', space_sdk='static', exist_ok=True,
                    private=False), budget, before=recheck)
            elif getattr(info, 'sdk', None) != 'static':
                raise OperationFailed('repo_info_sdk', None)
            run_operation('upload_folder', lambda: api.upload_folder(
                repo_id=space, repo_type='space', folder_path=str(folder), revision='main',
                delete_patterns=['*', '**/*'],
                commit_message=f'deploy PR #{self.number} {self.sha[:7]}'), budget, before=recheck)
        else:
            self.guard(action)
            try:
                api.delete_repo(repo_id=space, repo_type='space')
            except Exception as error:
                if status_of(error) != 404:
                    raise

    def comment(self, action, body):
        marker = '<!-- llamadart-chat-app-hf-pr-preview -->'
        comments = json.loads(subprocess.check_output([
            'gh', 'api', '--paginate', '--slurp',
            f'repos/{self.repository}/issues/{self.number}/comments?per_page=100']))
        existing = next((c for page in comments for c in page
                         if c['user']['login'] == 'github-actions[bot]' and marker in c['body']), None)
        endpoint = (f'repos/{self.repository}/issues/comments/{existing["id"]}' if existing
                    else f'repos/{self.repository}/issues/{self.number}/comments')
        self.guard(action)
        subprocess.run(['gh', 'api', '--method', 'PATCH' if existing else 'POST', endpoint,
                        '--input', '-'], input=json.dumps({'body': marker + '\n' + body}),
                       text=True, stdout=subprocess.DEVNULL, check=True)


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    preview = Preview(event)
    action = os.environ['PREVIEW_ACTION']
    if action not in ('build', 'cleanup'):
        raise ValueError('Expected build or cleanup')
    preview.guard(action)
    namespace = (os.environ.get('HF_CHAT_APP_PREVIEW_NAMESPACE')
                 or os.environ.get('HF_CHAT_APP_SPACE_REPO', '').split('/')[0])
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', namespace):
        raise ValueError('Set a valid HF preview namespace')
    space = f'{namespace}/llamadart-chat-pr-{preview.number}'
    app = f'https://{namespace.lower()}-llamadart-chat-pr-{preview.number}.static.hf.space'
    folder = Path('hf-space-sync')
    if action == 'build':
        preview.artifact()
        shutil.copytree('preview-artifact', folder)
        (folder / 'README.md').write_text(
            f'---\ntitle: llamadart chat app PR {preview.number}\nsdk: static\napp_file: index.html\n'
            'custom_headers:\n  cross-origin-embedder-policy: require-corp\n'
            '  cross-origin-opener-policy: same-origin\n  cross-origin-resource-policy: cross-origin\n---\n')
    from huggingface_hub import HfApi
    preview.mutate(action, HfApi(token=os.environ['HF_TOKEN']), space, folder)
    if action == 'build':
        preview.guard(action)
        subprocess.check_call(['bash', 'scripts/verify_chat_app_web_deployment.sh', app, preview.sha])
        body = f'Chat app preview for `{preview.sha[:7]}`: {app}\n\nSpace: https://huggingface.co/spaces/{space}'
    else:
        body = f'Chat app preview removed for `{space}`.'
    preview.comment(action, body)


if __name__ == '__main__':
    try:
        main()
    except Superseded:
        print('Preview event superseded by live PR state; remaining writes skipped.')
    except OperationFailed as error:
        raise SystemExit(str(error)) from None
    except Exception:
        # Provider exceptions may carry tokens or signed URLs; do not serialize them.
        raise SystemExit('Preview operation failed; no further writes attempted.') from None
