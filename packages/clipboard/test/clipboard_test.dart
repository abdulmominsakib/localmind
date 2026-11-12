import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard/clipboard.dart';

void main() {
  group('FlutterClipboard Tests', () {
    setUp(() async {
      // Clear any existing listeners before each test
      await FlutterClipboard.stopMonitoring();
      FlutterClipboard.removeAllListeners();
    });

    tearDown(() async {
      // Clean up after each test
      await FlutterClipboard.stopMonitoring();
      FlutterClipboard.removeAllListeners();
    });

    group('Basic Copy/Paste Operations', () {
      test('copy should throw exception for empty text', () async {
        expect(
          () => FlutterClipboard.copy(''),
          throwsA(isA<ClipboardException>()),
        );
      });

      test('copy should accept valid text', () async {
        expect(() => FlutterClipboard.copy('Hello World'), returnsNormally);
      });

      test('paste should return string', () async {
        final result = await FlutterClipboard.paste();
        expect(result, isA<String>());
      });

      test('controlC should return boolean', () async {
        final result = await FlutterClipboard.controlC('Test');
        expect(result, isA<bool>());
      });

      test('controlV should return dynamic data', () async {
        final result = await FlutterClipboard.controlV();
        expect(result, isA<EnhancedClipboardData>());
      });
    });

    group('Rich Text Operations', () {
      test('copyRichText should accept text and html', () async {
        expect(
          () => FlutterClipboard.copyRichText(
            text: 'Hello',
            html: '<b>Hello</b>',
          ),
          returnsNormally,
        );
      });

      test('copyRichText should throw for empty content', () async {
        expect(
          () => FlutterClipboard.copyRichText(text: '', html: ''),
          throwsA(isA<ClipboardException>()),
        );
      });

      test('pasteRichText should return EnhancedClipboardData', () async {
        final result = await FlutterClipboard.pasteRichText();
        expect(result, isA<EnhancedClipboardData>());
      });
    });

    group('Multiple Format Operations', () {
      test('copyMultiple should accept formats map', () async {
        final formats = {
          'text/plain': 'Hello',
          'text/html': '<b>Hello</b>',
        };
        expect(() => FlutterClipboard.copyMultiple(formats), returnsNormally);
      });

      test('copyMultiple should throw for empty formats', () async {
        expect(
          () => FlutterClipboard.copyMultiple({}),
          throwsA(isA<ClipboardException>()),
        );
      });
    });

    group('Callback Operations', () {
      test('copyWithCallback should call success callback', () async {
        bool successCalled = false;
        await FlutterClipboard.copyWithCallback(
          text: 'Test',
          onSuccess: () => successCalled = true,
        );
        expect(successCalled, isTrue);
      });

      test('copyWithCallback should call error callback on failure', () async {
        String? errorMessage;
        try {
          await FlutterClipboard.copyWithCallback(
            text: '',
            onError: (error) => errorMessage = error,
          );
        } catch (e) {
          // Expected to throw
        }
        expect(errorMessage, isNotNull);
      });
    });

    group('Utility Methods', () {
      test('isValidInput should validate text correctly', () {
        expect(FlutterClipboard.isValidInput(''), isFalse);
        expect(FlutterClipboard.isValidInput('   '), isFalse);
        expect(FlutterClipboard.isValidInput('Hello'), isTrue);
      });

      test('hasData should return boolean', () async {
        final result = await FlutterClipboard.hasData();
        expect(result, isA<bool>());
      });

      test('isEmpty should return boolean', () async {
        final result = await FlutterClipboard.isEmpty();
        expect(result, isA<bool>());
      });

      test('getDataSize should return integer', () async {
        final result = await FlutterClipboard.getDataSize();
        expect(result, isA<int>());
      });

      test('getContentType should return ClipboardContentType', () async {
        final result = await FlutterClipboard.getContentType();
        expect(result, isA<ClipboardContentType>());
      });
    });

    group('Clipboard Monitoring', () {
      test('addListener should add listener and return cleanup function', () {
        void testListener(EnhancedClipboardData data) {}
        final removeListener = FlutterClipboard.addListener(testListener);
        expect(removeListener, isA<Function>());
        expect(() => removeListener(), returnsNormally);
      });

      test('removeListener should remove listener', () {
        void testListener(EnhancedClipboardData data) {}
        FlutterClipboard.addListener(testListener);
        expect(() => FlutterClipboard.removeListener(testListener),
            returnsNormally);
      });

      test('removeAllListeners should remove all listeners', () {
        void testListener1(EnhancedClipboardData data) {}
        void testListener2(EnhancedClipboardData data) {}
        FlutterClipboard.addListener(testListener1);
        FlutterClipboard.addListener(testListener2);
        expect(() => FlutterClipboard.removeAllListeners(), returnsNormally);
      });

      test('startMonitoring should start monitoring', () async {
        expect(() => FlutterClipboard.startMonitoring(), returnsNormally);
        await FlutterClipboard.stopMonitoring();
      });

      test('stopMonitoring should stop monitoring', () async {
        await FlutterClipboard.startMonitoring();
        expect(() => FlutterClipboard.stopMonitoring(), returnsNormally);
      });
    });

    group('Debug and Testing', () {
      test('getDebugInfo should return map with monitoring info', () async {
        final result = await FlutterClipboard.getDebugInfo();
        expect(result, isA<Map<String, dynamic>>());
        expect(result.containsKey('listenersCount'), isTrue);
        expect(result.containsKey('isMonitoring'), isTrue);
        expect(result.containsKey('hasNativeMonitoring'), isTrue);
      });

      test('setMockData should set mock data', () async {
        expect(() => FlutterClipboard.setMockData('Test'), returnsNormally);
      });
    });

    group('EnhancedClipboardData Class', () {
      test('EnhancedClipboardData should have correct properties', () {
        final data = EnhancedClipboardData(
          text: 'Hello',
          html: '<b>Hello</b>',
          timestamp: DateTime.now(),
        );
        expect(data.text, equals('Hello'));
        expect(data.html, equals('<b>Hello</b>'));
        expect(data.timestamp, isNotNull);
      });

      test('EnhancedClipboardData isEmpty should work correctly', () {
        final emptyData = EnhancedClipboardData();
        final nonEmptyData = EnhancedClipboardData(text: 'Hello');

        expect(emptyData.isEmpty, isTrue);
        expect(nonEmptyData.isEmpty, isFalse);
      });

      test('EnhancedClipboardData hasText should work correctly', () {
        final emptyData = EnhancedClipboardData();
        final textData = EnhancedClipboardData(text: 'Hello');

        expect(emptyData.hasText, isFalse);
        expect(textData.hasText, isTrue);
      });
    });

    group('ClipboardException Class', () {
      test('ClipboardException should have message and code', () {
        final exception = ClipboardException('Test error', 'TEST_CODE');
        expect(exception.message, equals('Test error'));
        expect(exception.code, equals('TEST_CODE'));
      });

      test('ClipboardException toString should include message and code', () {
        final exception = ClipboardException('Test error', 'TEST_CODE');
        final string = exception.toString();
        expect(string, contains('Test error'));
        expect(string, contains('TEST_CODE'));
      });
    });
  });
}
