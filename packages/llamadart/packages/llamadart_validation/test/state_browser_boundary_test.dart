@TestOn('browser')
library;

import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/state_evidence.dart';
import 'package:test/test.dart';

void main() {
  test('common state contracts compile in browser and keep Web unqualified', () {
    final profile = ValidationProfile.fromJson({
      'schema_version': 1,
      'id': 'state-web-scope',
      'runtime': 'gguf',
      'backend': 'webgpu',
      'model': {
        'id': 'tiny-gguf',
        'revision': '99dd1a73db5a37100bd4ae633f4cfce6560e1567',
        'filename': 'stories15M.gguf',
        'sha256':
            '61b50d457809a5194818fd22e6724b456cd7bb9a6264c52c8110684c53f3704a',
        'bytes': 98357920,
        'kind': 'raw',
        'url':
            'https://huggingface.co/ggml-org/tiny-llamas/resolve/99dd1a73db5a37100bd4ae633f4cfce6560e1567/stories15M.gguf',
      },
      'selection': 'focused',
      'focus_features': ['state_persistence'],
      'context_size': 256,
      'threads': 4,
      'max_tokens': 1,
    });
    expect(PublicValidationEngine().isWeb, true);
    expect(
      expectedStateIdentityCapability(
        profile,
        web: true,
        diagnostics: {'backend_name': 'WebGPU'},
      ),
      false,
    );
    expect(profile.caseIds.where((id) => id.startsWith('P')), [
      'P01.capability',
      'P05.identity',
    ]);
    expect(
      expectedStateCapability(
        profile,
        web: true,
        diagnostics: {'backend_name': 'WebGPU'},
      ),
      null,
    );
  });
}
