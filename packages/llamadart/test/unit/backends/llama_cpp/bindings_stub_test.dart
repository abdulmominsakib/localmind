library;

import 'package:llamadart/src/backends/llama_cpp/bindings_stub.dart';
import 'package:test/test.dart';

void main() {
  // This is the branch pana analyzes and web builds link, so the messages are
  // the only diagnostic a web caller ever sees.
  test('every shim names itself as native-only', () {
    expect(
      llama_backend_init,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'llama_backend_init is only available on native platforms.',
        ),
      ),
    );
    expect(
      llama_backend_free,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'llama_backend_free is only available on native platforms.',
        ),
      ),
    );
    expect(
      llama_print_system_info,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'llama_print_system_info is only available on native platforms.',
        ),
      ),
    );
    expect(
      () => llama_dart_set_log_level(0),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'llama_dart_set_log_level is only available on native platforms.',
        ),
      ),
    );
  });
}
