import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main() {
  group('StableDiffusionRuntimeStatus', () {
    test('available status carries the probe answers and does not throw', () {
      const status = StableDiffusionRuntimeStatus.available(
        version: 'master-3f8527a',
        commit: '3f8527a',
        devices: [StableDiffusionDevice(name: 'MTL0', description: 'M4 Max')],
      );

      expect(status.isAvailable, isTrue);
      expect(status.unavailableReason, isNull);
      expect(status.version, 'master-3f8527a');
      expect(status.devices.single.name, 'MTL0');
      status.throwIfUnavailable();
    });

    test('unavailable status throws its LlamaUnsupportedException', () {
      final reason = LlamaUnsupportedException('missing');
      final status = StableDiffusionRuntimeStatus.unavailable(reason);

      expect(status.isAvailable, isFalse);
      expect(status.version, isNull);
      expect(status.devices, isEmpty);
      expect(status.throwIfUnavailable, throwsA(same(reason)));
    });
  });

  group('parseStableDiffusionDeviceList', () {
    test('splits name and description on the first tab', () {
      final devices = parseStableDiffusionDeviceList(
        'CPU\tApple M4 Max\nMTL0\tApple M4 Max (Metal)\tfamily 9\n',
      );

      expect(devices.map((device) => device.name), ['CPU', 'MTL0']);
      expect(devices.map((device) => device.description), [
        'Apple M4 Max',
        'Apple M4 Max (Metal)\tfamily 9',
      ]);
    });

    test('skips blank lines and keeps tab-less names', () {
      final devices = parseStableDiffusionDeviceList('\r\n  \nVulkan0\r\n');

      expect(devices, hasLength(1));
      expect(devices.single.name, 'Vulkan0');
      expect(devices.single.description, isEmpty);
    });

    test('empty output lists no devices', () {
      expect(parseStableDiffusionDeviceList(''), isEmpty);
    });
  });

  group('cpuInfoReportsRequiredArmFeatures', () {
    const dotProductCore =
        'processor\t: 0\n'
        'Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp '
        'asimdhp cpuid asimdrdm lrcpc dcpop asimddp\n';
    const baselineCore =
        'processor\t: 4\n'
        'Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid\n';

    test('accepts cores that all report dot-product and fp16', () {
      expect(cpuInfoReportsRequiredArmFeatures(dotProductCore * 2), isTrue);
    });

    test('rejects a core without asimddp, even beside cores with it', () {
      expect(cpuInfoReportsRequiredArmFeatures(baselineCore), isFalse);
      expect(
        cpuInfoReportsRequiredArmFeatures(dotProductCore + baselineCore),
        isFalse,
      );
    });

    test('rejects a dot-product core without fp16 arithmetic', () {
      expect(
        cpuInfoReportsRequiredArmFeatures(
          'Features\t: fp asimd atomics asimdrdm asimddp\n',
        ),
        isFalse,
      );
    });

    test('rejects a feature that only contains the name', () {
      expect(
        cpuInfoReportsRequiredArmFeatures(
          'Features\t: fp asimd asimddpx sve\n',
        ),
        isFalse,
      );
    });

    test('rejects input with no Features line', () {
      expect(cpuInfoReportsRequiredArmFeatures(''), isFalse);
      expect(
        cpuInfoReportsRequiredArmFeatures('flags\t: fpu vme de pse asimddp\n'),
        isFalse,
      );
    });
  });

  group('cpuInfoReportsRequiredX86Features', () {
    const haswellCore =
        'flags\t\t: fpu sse4_2 avx f16c fma bmi1 avx2 bmi2 popcnt\n';
    const sandyBridgeCore = 'flags\t\t: fpu sse4_2 avx popcnt\n';

    test('accepts cores that all report AVX2, FMA, F16C and BMI2', () {
      expect(cpuInfoReportsRequiredX86Features(haswellCore * 4), isTrue);
    });

    test('rejects a core without AVX2, even beside cores with it', () {
      expect(cpuInfoReportsRequiredX86Features(sandyBridgeCore), isFalse);
      expect(
        cpuInfoReportsRequiredX86Features(haswellCore + sandyBridgeCore),
        isFalse,
      );
    });

    test('rejects AVX2 without FMA or F16C', () {
      expect(
        cpuInfoReportsRequiredX86Features('flags\t: avx avx2 bmi2 f16c\n'),
        isFalse,
      );
      expect(
        cpuInfoReportsRequiredX86Features('flags\t: avx avx2 bmi2 fma\n'),
        isFalse,
      );
    });

    test('rejects input with no flags line', () {
      expect(cpuInfoReportsRequiredX86Features(''), isFalse);
      expect(
        cpuInfoReportsRequiredX86Features('Features\t: avx2 fma f16c bmi2\n'),
        isFalse,
      );
    });
  });
}
