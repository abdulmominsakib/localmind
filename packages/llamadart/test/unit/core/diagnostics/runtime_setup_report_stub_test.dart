import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/diagnostics/runtime_setup_report_stub.dart';
import 'package:test/test.dart';

void main() {
  test('unsupported collector names the desktop and app validation scope', () {
    expect(
      collectRuntimeSetupReport,
      throwsA(
        isA<LlamaUnsupportedException>()
            .having(
              (error) => error.message,
              'desktop scope',
              contains('Windows'),
            )
            .having((error) => error.message, 'Web scope', contains('Web'))
            .having(
              (error) => error.message,
              'mobile scope',
              contains('mobile'),
            )
            .having(
              (error) => error.message,
              'guidance',
              contains('validation'),
            ),
      ),
    );
  });
}
