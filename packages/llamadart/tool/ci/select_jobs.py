#!/usr/bin/env python3
"""Conservative CI impact selection and truthful conditional-job aggregation.

Only enumerated independent paths may omit work. Missing revisions, malformed
Git output, unknown inputs and runtime/shared changes select the full graph.
Uses Git's NUL-delimited, rename-aware inventory rather than GitHub's capped
changed-files API. No changed path is evaluated as shell text.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

COMPANIONS = (
    'llamadart_llama_cpp_flutter', 'llamadart_litert_lm_flutter',
    'llamadart_stable_diffusion_flutter',
)
CORE_JOBS = (
    'analyze', 'docs-check', 'docs-versions', 'validation-harness',
    'validation-integration', 'companion-packages', 'test-linux-coverage',
    'test-web', 'web-chat-contract', 'test-other-os',
    'native-prompt-reuse-parity', 'artifact-contract',
    'genkit', 'example-packages', 'model-store', 'markdown-tests',
)
# Jobs outside the plan that run exactly when the planned job they feed is
# selected: the Linux VM test shards. The planned test-linux-coverage job only
# merges their coverage, which runs after merge (push and manual runs).
SHARD_JOBS = {'test-linux-vm': 'test-linux-coverage'}
# The companion-packages job also hosts macOS steps selected apart from the
# packages, so it runs, and must succeed, when any of these checks is selected.
COMPANION_JOB_CHECKS = ('companion-packages', 'test-other-os', 'validation-harness')
DESKTOPS = ('ubuntu-24.04', 'windows-2022', 'macos-15')
APPS = ('android', 'web', 'ios-inputs')
# Bundle targets a pull request builds only when it changes their own build
# inputs; pushes to main and manual runs build them for every selecting change.
# Their Dart code also compiles in the Linux desktop and Web builds.
_BUNDLE_WORKFLOW = ('.github/workflows/validation_bundles.yml', 'tool/ci/select_jobs.py')
_NATIVE_BUILD_INPUTS = ('hook/', 'lib/src/hook/', 'pubspec.yaml', 'pubspec.lock',
                        'tool/testing/validation/', 'tool/testing/validation.dart')
POST_MERGE_TARGETS = {
    'macos-15': _BUNDLE_WORKFLOW + _NATIVE_BUILD_INPUTS,
    'android': _BUNDLE_WORKFLOW + _NATIVE_BUILD_INPUTS + tuple(
        'packages/' + name + '/' + part for name in COMPANIONS
        for part in ('lib/', 'pubspec.yaml')),
}
# Imported by tool/testing/validation/image_profile.dart, whose root tests run
# in validation-integration.
VALIDATION_IMPORTED_CHAT_APP_FILES = (
    'example/chat_app/lib/models/image_model_profile.dart',
    'example/chat_app/integration_test/support/image_evidence.dart',
    'example/chat_app/integration_test/support/image_settings_evidence.dart',
)
# The validation package's `flutter.assets`, which the chat app bundles.
VALIDATION_BUNDLED_ASSETS = (
    'packages/llamadart_validation/assets/profiles/',
    'packages/llamadart_validation/assets/decision/',
    'packages/llamadart_validation/assets/embeddings/v1/',
)

def inventory(raw):
    """Return both endpoints of renames/copies and deleted paths; reject truncation."""
    parts = raw.decode('utf-8', errors='strict').split('\0')
    if parts.pop() != '':
        raise ValueError('Git inventory must end in NUL')
    paths = []
    while parts:
        status = parts.pop(0)
        if not re.fullmatch(r'(?:[AMDUT]|[RC][0-9]{1,3})', status):
            raise ValueError('Unsupported Git status')
        count = 2 if status[0] in 'RC' else 1
        if len(parts) < count:
            raise ValueError('Truncated Git inventory')
        for _ in range(count):
            path = parts.pop(0)
            if not path or path.startswith('/') or '..' in PurePosixPath(path).parts:
                raise ValueError('Invalid Git path')
            paths.append(path)
    return paths


def builds_target(target, path):
    """Whether a pull request changing [path] builds a post-merge [target]."""
    if path.startswith(POST_MERGE_TARGETS[target]):
        return True
    if path.startswith('packages/llamadart_validation/'):
        return not path.startswith(('packages/llamadart_validation/test/',
                                    'packages/llamadart_validation/assets/',
                                    'packages/llamadart_validation/schemas/'))
    if target == 'android' and path.startswith('example/chat_app/'):
        return not (path.endswith('.md') or path.startswith(tuple(
            'example/chat_app/' + part + '/'
            for part in ('test', 'test_vm', 'web', 'ios', 'macos', 'linux', 'windows'))))
    return False


def select(paths, force_full=False, pull_request=False):
    jobs, companions, desktops, apps = set(), set(), set(), set()
    reasons = []

    def full(reason):
        # Do not clear an artifact check selected by another changed path.
        jobs.update(job for job in CORE_JOBS if job != 'artifact-contract')
        companions.update(COMPANIONS)
        desktops.update(DESKTOPS)
        apps.update(APPS)
        reasons.append(reason)

    if force_full or not paths:
        full('manual, missing or unavailable change inventory')
        jobs.add('artifact-contract')
    for path in paths:
        if path.startswith(('.github/workflows/', '.github/actions/', 'tool/ci/', 'test/ci/')):
            full('workflow or selector change')
            jobs.add('artifact-contract')
        elif path == 'website/docs/integrations/genkit.md':
            jobs.update(('docs-check', 'docs-versions', 'genkit'))
        elif path.startswith('packages/genkit_llamadart/'):
            jobs.add('genkit')
        elif path == 'website/docs/guides/model-store.md':
            jobs.update(('docs-check', 'docs-versions', 'model-store'))
        elif path.startswith('packages/llamadart_model_store/'):
            jobs.add('model-store')
        elif (path in ('README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'AGENTS.md', 'LICENSE')
              or path.startswith(('doc/', 'website/', 'tool/docs/'))
              or (path.startswith(('packages/', 'example/')) and path.endswith('.md'))):
            jobs.update(('docs-check', 'docs-versions'))
        elif any(path.startswith('packages/' + name + '/') for name in COMPANIONS):
            name = path.split('/')[1]
            companions.add(name)
            # Root hooks/loaders and Flutter consumers depend on companions.
            jobs.update(('analyze', 'companion-packages', 'test-linux-coverage',
                         'test-other-os', 'web-chat-contract'))
            apps.update(APPS)
        elif path.startswith('packages/llamadart_validation/'):
            jobs.update(('analyze', 'validation-harness', 'validation-integration'))
            compiled = not path.startswith(('packages/llamadart_validation/test/',
                                            'packages/llamadart_validation/assets/',
                                            'packages/llamadart_validation/schemas/'))
            if compiled or path.startswith(VALIDATION_BUNDLED_ASSETS):
                # The chat app depends on this package, so it is a deployed input.
                jobs.add('web-chat-contract')
            if compiled:
                desktops.update(DESKTOPS)
                apps.update(APPS)
        elif path.startswith(('tool/testing/validation/', 'tool/testing/validation.dart')):
            jobs.update(('analyze', 'validation-harness', 'validation-integration'))
            # Build/orchestration helpers are shared between all bundle targets.
            desktops.update(DESKTOPS)
            apps.update(APPS)
        elif path.startswith('example/chat_app/android/'):
            jobs.add('analyze')
            apps.add('android')
        elif path.startswith('example/chat_app/ios/'):
            jobs.add('analyze')
            apps.add('ios-inputs')
        elif path.startswith('example/chat_app/web/'):
            jobs.update(('analyze', 'web-chat-contract'))
            apps.add('web')
        elif path.startswith(('example/chat_app/test/', 'example/chat_app/test_vm/')):
            jobs.update(('analyze', 'web-chat-contract'))
        elif path.startswith('example/chat_app/'):
            jobs.update(('analyze', 'web-chat-contract', 'validation-harness'))
            if path in VALIDATION_IMPORTED_CHAT_APP_FILES:
                jobs.add('validation-integration')
            apps.update(APPS)
        elif path.startswith('test/'):
            # Preserve all root test inventories, including platform-sensitive tests.
            jobs.update(('analyze', 'test-linux-coverage', 'test-web', 'test-other-os'))
        else:
            full('shared/runtime or unclassified path: ' + path)
        # Root tests scan all maintained Markdown, including independent package
        # docs and the Genkit gateway handled above. Keep this additive so a
        # specialized path cannot bypass those repository-wide contracts.
        # These helpers are followed by the reader-inventory guard. A helper
        # can start reading Markdown without changing its root test suite.
        if (path.endswith('.md') or path.startswith(('tool/docs/',
                                                   'tool/testing/validation/'))
                or path == 'tool/testing/validation.dart'):
            jobs.add('markdown-tests')
    if 'analyze' in jobs:
        jobs.discard('docs-versions')  # Already included in root static validation.
    if 'test-linux-coverage' in jobs:
        jobs.discard('markdown-tests')  # Linux coverage runs every root test.
    if 'test-linux-coverage' in jobs and 'web-chat-contract' in jobs:
        # Both root provider tests and all Flutter consumer tests are covered.
        jobs.discard('validation-integration')
    if pull_request and paths and not force_full:
        for target in POST_MERGE_TARGETS:
            if not any(builds_target(target, path) for path in paths):
                desktops.discard(target)
                apps.discard(target)
    return {
        'schema_version': 1,
        'jobs': {job: job in jobs for job in CORE_JOBS},
        # PRs skip coverage; main and manual runs collect and enforce it.
        'coverage': not pull_request,
        'companions': ['packages/' + name for name in COMPANIONS if name in companions],
        'desktops': [name for name in DESKTOPS if name in desktops],
        'apps': [name for name in APPS if name in apps],
        'reasons': reasons,
    }


def validate_plan(plan):
    if not isinstance(plan, dict) or plan.get('schema_version') != 1:
        raise ValueError('Unsupported plan schema')
    jobs = plan.get('jobs')
    if not isinstance(jobs, dict) or set(jobs) != set(CORE_JOBS):
        raise ValueError('Incomplete job selection')
    if any(type(value) is not bool for value in jobs.values()):
        raise ValueError('Selections must be boolean')
    if type(plan.get('coverage')) is not bool:
        raise ValueError('Coverage selection must be boolean')
    for field, allowed in (
        ('companions', ['packages/' + name for name in COMPANIONS]),
        ('desktops', DESKTOPS), ('apps', APPS),
    ):
        values = plan.get(field)
        if not isinstance(values, list) or any(not isinstance(v, str) or v not in allowed for v in values):
            raise ValueError('Invalid target matrix')
        if len(values) != len(set(values)):
            raise ValueError('Duplicate target')
    if jobs['companion-packages'] != bool(plan['companions']):
        raise ValueError('Companion matrix disagrees with job selection')


def expected_jobs(plan, bundle=False):
    """Whether each job the aggregate needs, other than `changes`, is selected."""
    if bundle:
        return {'desktop': bool(plan['desktops']), 'app': bool(plan['apps'])}
    return {
        **plan['jobs'],
        **{job: plan['jobs'][fed] for job, fed in SHARD_JOBS.items()},
        'test-linux-coverage': plan['jobs']['test-linux-coverage'] and plan['coverage'],
        'companion-packages': companion_job_selected(plan),
    }


def companion_job_selected(plan):
    return any(plan['jobs'][check] for check in COMPANION_JOB_CHECKS)


def validation_harness_oses(plan):
    """Windows runs the harness test in Test Native whenever that job is selected."""
    return ['ubuntu-latest'] + ([] if plan['jobs']['test-other-os'] else ['windows-latest'])


def aggregate(plan, needs, bundle=False):
    """A selected job must succeed; only intentionally unselected jobs may skip."""
    validate_plan(plan)
    expected = expected_jobs(plan, bundle)
    errors = []
    if needs.get('changes', {}).get('result') != 'success':
        errors.append('change selection did not succeed')
    if set(needs) != set(expected) | {'changes'}:
        errors.append('aggregate dependency inventory differs from plan')
    for job, selected in expected.items():
        result = needs.get(job, {}).get('result')
        if result != ('success' if selected else 'skipped'):
            errors.append(f'{job}: selected={selected}, result={result}')
    return errors


def event_paths(event_name, event):
    if event_name == 'pull_request':
        base = event['pull_request']['base']['sha']
        head = event['pull_request']['head']['sha']
        mode = 'pr'
    elif event_name == 'push':
        base, head, mode = event['before'], event['after'], 'push'
    else:
        raise ValueError('No incremental selection for this event')
    if not all(re.fullmatch(r'[0-9a-f]{40}', ref) and int(ref, 16) for ref in (base, head)):
        raise ValueError('Invalid revision')
    if mode == 'pr':
        base = subprocess.check_output(['git', 'merge-base', base, head], text=True).strip()
    raw = subprocess.check_output(['git', 'diff', '--name-status', '-z', '-M', base, head, '--'])
    return inventory(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('select', 'aggregate'))
    parser.add_argument('--bundle', action='store_true')
    args = parser.parse_args()
    if args.command == 'aggregate':
        try:
            errors = aggregate(json.loads(os.environ['PLAN']), json.loads(os.environ['NEEDS']), args.bundle)
        except (KeyError, ValueError, TypeError) as error:
            errors = [f'Invalid aggregate input: {error}']
        for error in errors:
            print(error, file=sys.stderr)
        return int(bool(errors))
    pull_request = os.environ.get('GITHUB_EVENT_NAME') == 'pull_request'
    try:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        plan = select(event_paths(os.environ['GITHUB_EVENT_NAME'], event),
                      pull_request=pull_request)
    except (KeyError, ValueError, TypeError, OSError, subprocess.SubprocessError) as error:
        plan = select([], force_full=True, pull_request=pull_request)
        plan['reasons'] = ['Full fallback: ' + type(error).__name__]
    encoded = json.dumps(plan, separators=(',', ':'))
    print(json.dumps(plan, indent=2))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write('plan=' + encoded + '\n')
        for name, selected in plan['jobs'].items():
            out.write(f'{name}={str(selected).lower()}\n')
        out.write(f'companion-job={str(companion_job_selected(plan)).lower()}\n')
        out.write(f'coverage={str(plan["coverage"]).lower()}\n')
        out.write('validation-harness-os=' + json.dumps(validation_harness_oses(plan), separators=(',', ':')) + '\n')
        for name in ('companions', 'desktops', 'apps'):
            out.write(name + '=' + json.dumps(plan[name], separators=(',', ':')) + '\n')
            out.write(name + '-enabled=' + str(bool(plan[name])).lower() + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
