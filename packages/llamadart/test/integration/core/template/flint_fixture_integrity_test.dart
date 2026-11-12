@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../../support/flint_template_fixture.dart';

void main() {
  test('browser Flint fixture is the exact licensed upstream capture', () {
    final source = File('test/fixtures/flint/Flint.jinja').readAsStringSync();
    final capture = File(
      'test/fixtures/flint/render_upstream.json',
    ).readAsStringSync();

    expect(flintTemplate, source);
    expect(flintUpstreamJson, capture);
    expect(
      sha256.convert(utf8.encode(source)).toString(),
      flintUpstream['template_sha256'],
    );
    expect(flintCases, hasLength(7));
  });
}
