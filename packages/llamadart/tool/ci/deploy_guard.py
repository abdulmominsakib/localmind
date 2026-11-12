#!/usr/bin/env python3
"""Decide whether a hosted-demo build is still current once `main` has moved.

A build stays deployable while `main`'s tip has the same demo inputs. Once they
differ, the newer commits supersede the build: they have, or need, a deploy run
of their own, so the older build ends neutrally instead of failing. Only a
build `main` no longer contains, or a Git failure, is an error.
"""
import base64
import os
import re
import subprocess
import sys

from select_jobs import inventory, select

# The workflow's `on.push.paths`; ci_workflow_selection_test.dart pins equality.
LAYA_TETRIS_INPUTS = (
    'example/laya_tetris/**',
    'lib/**',
    'hook/**',
    'pubspec.yaml',
    'scripts/fetch_webgpu_bridge_assets.sh',
    '.github/workflows/laya_tetris_hf_static_deploy.yml',
)
DEMOS = ('chat-app', 'laya-tetris')
MAIN_REF = 'refs/remotes/origin/main'


def is_input(demo, path):
    if demo == 'chat-app':
        # A push of this path alone would build, test and deploy the chat app.
        return select([path])['jobs']['web-chat-contract']
    return any(path.startswith(pattern[:-2]) if pattern.endswith('/**') else path == pattern
               for pattern in LAYA_TETRIS_INPUTS)


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def fetch_main():
    """Read `main`'s tip and the history up to it; the checkout keeps no credentials."""
    env = dict(os.environ)
    token = env.get('GH_TOKEN')
    if token:
        server = env.get('GITHUB_SERVER_URL', 'https://github.com')
        basic = base64.b64encode(f'x-access-token:{token}'.encode()).decode()
        # Environment configuration keeps the credential out of argv and .git/config.
        env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0=f'http.{server}/.extraheader',
                   GIT_CONFIG_VALUE_0=f'AUTHORIZATION: basic {basic}')
    subprocess.check_call(['git', 'fetch', '--quiet', '--no-tags', 'origin',
                           '+refs/heads/main:' + MAIN_REF], env=env)
    return git('rev-parse', MAIN_REF)


def newer_inputs(demo, deploy_sha, main_sha):
    """Demo inputs that differ between the build and main's tip."""
    if subprocess.run(['git', 'merge-base', '--is-ancestor', deploy_sha, main_sha]).returncode:
        raise ValueError(f'main ({main_sha}) does not contain {deploy_sha}')
    # Git records no push boundaries, so only the whole range is compared. An
    # input that differs here changed in some later push, which had a deploy run;
    # one changed and restored leaves this build equal to main for the demo.
    paths = inventory(subprocess.check_output(
        ['git', 'diff', '--name-status', '-z', '-M', deploy_sha, main_sha, '--']))
    return sorted({path for path in paths if is_input(demo, path)})


def verdict(demo, deploy_sha, main_sha, inputs):
    """Return (deploy, title, message) for the compared revisions."""
    if main_sha == deploy_sha:
        return True, 'Deploying main', f'{deploy_sha} is the tip of main.'
    if not inputs:
        return True, 'Deploying behind main', (
            f'main moved to {main_sha} without changing {demo} inputs, so {deploy_sha} '
            'is still its current build.')
    shown = ', '.join(inputs[:3]) + (f' and {len(inputs) - 3} more' if len(inputs) > 3 else '')
    return False, 'Deploy skipped: superseded', (
        f'{deploy_sha} was not deployed: main is at {main_sha} and commits after this build '
        f'change {demo} inputs ({shown}). The deploy run of the newer commit publishes them; '
        'if none ran, redeploy main by hand (doc/ci_selection.md).')


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in DEMOS:
        raise ValueError('Expected one of: ' + ', '.join(DEMOS))
    demo, deploy_sha = sys.argv[1], os.environ['DEPLOY_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', deploy_sha):
        raise ValueError('Invalid deploy revision')
    main_sha = fetch_main()
    inputs = [] if main_sha == deploy_sha else newer_inputs(demo, deploy_sha, main_sha)
    deploy, title, message = verdict(demo, deploy_sha, main_sha, inputs)
    # Changed paths are repository data; keep them from forming workflow commands.
    escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(escaped if main_sha == deploy_sha else f'::notice title={title}::{escaped}')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
        summary.write(f'**{title}** ({demo}): ' + ' '.join(message.split()) + '\n')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'deploy={str(deploy).lower()}\n')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'::error title=Deploy guard failed::{error}')
