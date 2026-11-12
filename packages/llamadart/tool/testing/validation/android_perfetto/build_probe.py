#!/usr/bin/env python3
"""Build the model-free Android probe offline and freeze its input/APK identity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_inputs(project):
    inputs = {}
    for path in project.rglob('*'):
        if not path.is_file() or any(part in ('.gradle', 'build', '__pycache__') for part in path.relative_to(project).parts):
            continue
        if path.name != 'local.properties':
            inputs[str(path.relative_to(project))] = digest(path)
    return dict(sorted(inputs.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gradle', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--allow-dirty', action='store_true', help='Local review only; cannot submit these APKs')
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    root = project.parents[3]
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root))
    if dirty and not args.allow_dirty:
        parser.error('Commit the reviewed source before creating a submittable bundle')
    if not os.environ.get('ANDROID_HOME') or not os.environ.get('JAVA_HOME'):
        parser.error('ANDROID_HOME and JAVA_HOME must name existing pinned SDK/JDK installations')
    if args.output.resolve().is_relative_to(root):
        parser.error('Frozen output must be outside the source checkout')
    if args.output.exists():
        parser.error('Output must be a fresh directory')
    inputs = source_inputs(project)
    gradle_version = subprocess.check_output([str(args.gradle.resolve()), '--offline', '--version'], text=True)
    if 'Gradle 8.14\n' not in gradle_version:
        parser.error('Expected pinned Gradle 8.14')
    java = Path(os.environ['JAVA_HOME']) / 'bin/java'
    jdk_version = subprocess.run([str(java), '-version'], text=True, capture_output=True, check=True).stderr
    sdk = Path(os.environ['ANDROID_HOME'])
    tool_digests = {'java': digest(java), 'gradle_launcher': digest(args.gradle.resolve()),
                    'android_sdk_36_jar': digest(sdk / 'platforms/android-36/android.jar'),
                    'android_aapt2_35_0_0': digest(sdk / 'build-tools/35.0.0/aapt2')}
    subprocess.run([str(args.gradle.resolve()), '--offline', '--no-daemon', '-p', str(project),
                    'app:testDebugUnitTest', 'app:assembleDebug', 'app:assembleDebugAndroidTest'], check=True)
    final_source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    final_dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root))
    if source != final_source or dirty != final_dirty or inputs != source_inputs(project):
        parser.error('Source changed during build; discard APKs and rebuild from reviewed source')
    args.output.mkdir(parents=True)
    files = {}
    for original, name in [('app/build/outputs/apk/debug/app-debug.apk', 'app.apk'),
                           ('app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk', 'test.apk')]:
        target = args.output / name
        shutil.copyfile(project / original, target)
        files[name] = {'sha256': digest(target), 'bytes': target.stat().st_size}
    manifest = {'schema_version': 1, 'scope': 'model_free_trace_collection_capability',
                'source_commit': source, 'source_dirty': dirty, 'submittable': not dirty,
                'gpu_inference_qualified': False, 'source_inputs': inputs, 'files': files, 'jdk_version': jdk_version,
                'gradle_version': gradle_version, 'tool_sha256': tool_digests}
    (args.output / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
