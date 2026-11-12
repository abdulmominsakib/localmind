#!/usr/bin/env python3
"""Validate pub's selected files and resolve consumers from that exact file set.

No publication, model download or native build is performed. Run after workspace
preparation from a clean checkout, with CI's pinned Dart SDK on PATH.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def archive_files(output, root):
    """Read the pinned SDK's verbose archive inventory; fail on format drift."""
    marker = 'FINE: Creating .tar.gz stream containing:\n'
    if output.count(marker) != 1:
        raise ValueError('pub did not report exactly one archive inventory')
    root = root.resolve()
    files = []
    for line in output.split(marker, 1)[1].splitlines():
        if not line.startswith('    | '):
            break
        source = Path(line[6:])
        if not source.is_absolute():
            raise ValueError('pub reported a non-absolute archive path')
        resolved = source.resolve()
        if resolved != root and root not in resolved.parents:
            raise ValueError('archive source escapes the package root')
        if source.is_dir():
            continue
        if not source.is_file():
            raise ValueError('archive source is not a file')
        relative = source.relative_to(root).as_posix()
        if relative in files:
            raise ValueError('duplicate archive file')
        files.append(relative)
    if 'pubspec.yaml' not in files or 'lib/llamadart.dart' not in files:
        raise ValueError('incomplete pub archive inventory')
    return files


def archive_errors(files):
    """Keep checkout-only dependencies together and runnable examples present."""
    errors = []
    for prefix in ('packages/llamadart_validation/', 'example/chat_app/',
                   'packages/genkit_llamadart/', 'packages/llamadart_model_store/'):
        if any(path.startswith(prefix) for path in files):
            errors.append('checkout-only files included: ' + prefix)
    for required in ('pubspec.yaml', 'lib/llamadart.dart', 'hook/build.dart',
                     'example/basic_app/pubspec.yaml',
                     'example/basic_app/bin/llamadart_litert_embedding_example.dart'):
        if required not in files:
            errors.append('required packaged example/runtime file missing: ' + required)
    return errors


def check(root, dart='dart'):
    published = subprocess.run(
        [dart, 'pub', '--verbose', 'publish', '--dry-run'], cwd=root,
        capture_output=True, text=True, timeout=300)
    if published.returncode:
        diagnostic_limit = 16 * 1024
        raise RuntimeError(
            'pub dry-run failed (exit %s)\nstdout (tail):\n%s\nstderr (tail):\n%s' %
            (published.returncode, published.stdout[-diagnostic_limit:],
             published.stderr[-diagnostic_limit:]))
    files = archive_files(published.stdout + published.stderr, root)
    errors = archive_errors(files)
    if errors:
        raise ValueError('; '.join(errors))
    with tempfile.TemporaryDirectory(prefix='llamadart-pub-consumer-') as scratch:
        package = Path(scratch) / 'package'
        for path in files:
            target = package / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / path, target)
        consumer = Path(scratch) / 'consumer'
        consumer.mkdir()
        (consumer / 'pubspec.yaml').write_text(
            'name: llamadart_archive_consumer\npublish_to: none\n'
            'environment:\n  sdk: ">=3.10.7 <4.0.0"\n'
            'dependencies:\n  llamadart:\n    path: ../package\n')
        (consumer / 'main.dart').write_text(
            "import 'package:llamadart/llamadart.dart';\n"
            "void main() { print(const LlamaTextContent('Archive consumer')); }\n")
        for cwd, arguments in (
            (consumer, ['pub', 'get']),
            (consumer, ['analyze', 'main.dart']),
            (package / 'example/basic_app', ['pub', 'get']),
            (package / 'example/basic_app', ['analyze', 'bin']),
        ):
            result = subprocess.run([dart, *arguments], cwd=cwd,
                                    capture_output=True, text=True, timeout=300)
            if result.returncode:
                # These SDK commands contain no credentials or model inputs.
                raise RuntimeError('extracted-package consumer failed: dart ' +
                                   ' '.join(arguments) + '\n' +
                                   result.stdout + result.stderr)
    print('Core pub dry-run passed; %s files staged; fresh consumer and packaged '
          'basic example resolved and analyzed without checkout-only packages.' % len(files))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    try:
        check(args.root.resolve(), args.dart)
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
