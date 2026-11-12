import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

LlamaStateIdentity _identity({
  String runtimeBuild = 'llamadart-native-build/1;owner=abc;backends=cpu',
  int sessionFormatVersion = 11,
  int contextSize = 256,
  String contextConfigDigest = 'digest-a',
}) => LlamaStateIdentity(
  runtimeBuild: runtimeBuild,
  sessionFormatVersion: sessionFormatVersion,
  contextSize: contextSize,
  contextConfigDigest: contextConfigDigest,
);

void main() {
  test('matches an identity with every field equal', () {
    expect(_identity().matches(_identity()), isTrue);
    expect(_identity(), _identity());
    expect(_identity().hashCode, _identity().hashCode);
  });

  test('does not match when any one field differs', () {
    final base = _identity();
    for (final other in [
      _identity(runtimeBuild: 'llamadart-native-build/1;owner=def'),
      _identity(sessionFormatVersion: 10),
      _identity(contextSize: 512),
      _identity(contextConfigDigest: 'digest-b'),
    ]) {
      expect(base.matches(other), isFalse, reason: '$other');
      expect(other.matches(base), isFalse, reason: '$other');
      expect(base == other, isFalse, reason: '$other');
      expect(other.hashCode, isNot(base.hashCode), reason: '$other');
    }
  });

  test('rejects an identity without a runtime build', () {
    for (final build in ['', '  ']) {
      expect(
        () => _identity(runtimeBuild: build),
        throwsA(
          isA<LlamaArgumentException>().having(
            (e) => e.name,
            'name',
            'runtimeBuild',
          ),
        ),
      );
    }
  });

  test('rejects non-positive versions and sizes and an empty digest', () {
    for (final (create, name) in <(LlamaStateIdentity Function(), String)>[
      (() => _identity(sessionFormatVersion: 0), 'sessionFormatVersion'),
      (() => _identity(contextSize: 0), 'contextSize'),
      (() => _identity(contextSize: -1), 'contextSize'),
      (() => _identity(contextConfigDigest: ''), 'contextConfigDigest'),
    ]) {
      expect(
        create,
        throwsA(
          isA<LlamaArgumentException>().having((e) => e.name, 'name', name),
        ),
      );
    }
  });
}
