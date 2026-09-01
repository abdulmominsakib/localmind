import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/on_device_error_formatter.dart';

void main() {
  group('formatOnDeviceError', () {
    test(
      'returns generic unsupported message for BuiltInAiUnavailableException',
      () {
        const error =
            'BuiltInAiUnavailableException(BuiltInAiAvailability.unavailableDeviceUnsupported): Built-in AI is not available: BuiltInAiAvailability.unavailableDeviceUnsupported';
        final formatted = formatOnDeviceError(error);
        expect(formatted, 'Built-in AI is not supported on this device.');
      },
    );

    test('returns generic unsupported message when isBuiltIn is true', () {
      final formatted = formatOnDeviceError(
        Exception('Some internal failure'),
        isBuiltIn: true,
      );
      expect(formatted, 'Built-in AI is not supported on this device.');
    });

    test('returns generic unsupported message for unavailableOther', () {
      const error = 'BuiltInAiAvailability.unavailableOther';
      final formatted = formatOnDeviceError(error);
      expect(formatted, 'Built-in AI is not supported on this device.');
    });

    test('formats missing hugging face token error cleanly', () {
      const error = 'missing_huggingface_token';
      final formatted = formatOnDeviceError(error);
      expect(formatted, contains('Hugging Face token required'));
    });

    test('formats disk space error cleanly', () {
      const error =
          'FileSystemException: write failed, OS Error: No space left on device, errno = 28';
      final formatted = formatOnDeviceError(error);
      expect(formatted, contains('Not enough storage space'));
    });

    test('formats network / socket error cleanly', () {
      const error = 'SocketException: Failed host lookup: huggingface.co';
      final formatted = formatOnDeviceError(error);
      expect(formatted, contains('Network connection failed'));
    });

    test('strips Exception prefix from standard Dart exceptions', () {
      final formatted = formatOnDeviceError(Exception('Custom error message'));
      expect(formatted, 'Custom error message');
    });
  });
}
