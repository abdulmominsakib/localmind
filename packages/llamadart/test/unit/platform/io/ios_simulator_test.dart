@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/platform/io/ios_simulator.dart';
import 'package:test/test.dart';

String? Function(String) _variables(Map<String, String> values) =>
    (name) => values[name];

void main() {
  group('isIosSimulatorProcess', () {
    test('is true on iOS when CoreSimulator set SIMULATOR_UDID', () {
      final read = <String>[];

      expect(
        isIosSimulatorProcess(
          isIOS: true,
          readVariable: (name) {
            read.add(name);
            return '37DBE438-8349-45D8-AC13-18917E5AD9A6';
          },
        ),
        isTrue,
      );
      expect(read, ['SIMULATOR_UDID']);
    });

    test('is false on an iOS device, which has no SIMULATOR_UDID', () {
      expect(
        isIosSimulatorProcess(
          isIOS: true,
          readVariable: _variables(const {'HOME': '/var/mobile'}),
        ),
        isFalse,
      );
      expect(
        isIosSimulatorProcess(
          isIOS: true,
          readVariable: _variables(const {'SIMULATOR_UDID': ''}),
        ),
        isFalse,
      );
    });

    test('is false off iOS without reading the variable', () {
      expect(
        isIosSimulatorProcess(
          isIOS: false,
          readVariable: (name) => fail('read $name off iOS'),
        ),
        isFalse,
      );
    });

    test('is false on the host that runs the tests', () {
      expect(Platform.isIOS, isFalse);
      expect(isIosSimulatorProcess(), isFalse);
    });
  });
}
