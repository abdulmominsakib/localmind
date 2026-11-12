@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_memory.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

import '../../../../tool/testing/validation/process.dart';
import '../../../support/fake_stable_diffusion_runtime.dart';

const _gib = 1 << 30;

const _memInfo = '''
MemTotal:        5750000 kB
MemFree:          300000 kB
MemAvailable:    2097152 kB
Buffers:           10000 kB
''';

const _status = '''
Name:	llamadart_chat_example
VmPeak:	  9000000 kB
VmRSS:	   307200 kB
''';

void main() {
  group('parseProcMemoryBytes', () {
    test('reads a kB field in bytes', () {
      expect(parseProcMemoryBytes(_memInfo, 'MemAvailable'), 2097152 * 1024);
      expect(parseProcMemoryBytes(_memInfo, 'MemTotal'), 5750000 * 1024);
      expect(parseProcMemoryBytes(_status, 'VmRSS'), 300 << 20);
    });

    test('is null without the field', () {
      expect(
        parseProcMemoryBytes('MemTotal: 5750000 kB\n', 'MemAvailable'),
        isNull,
      );
      expect(parseProcMemoryBytes('', 'MemAvailable'), isNull);
      expect(parseProcMemoryBytes(_status, 'VmHWM'), isNull);
    });
  });

  group('readStableDiffusionMemoryBudget', () {
    ({int bytes, String source})? read(
      Abi abi, {
      String? memInfo,
      String? status,
      int? ios,
      int? macos,
      int? metal,
      ImageGenerationComputeDevice device = ImageGenerationComputeDevice.cpu,
    }) => readStableDiffusionMemoryBudget(
      device: device,
      abi: abi,
      readMemInfo: () => memInfo,
      readProcessStatus: () => status,
      iosAvailableMemory: () => ios,
      macosPhysicalMemory: () => macos,
      metalRecommendedWorkingSet: () => metal,
    );

    test('uses MemAvailable on Linux', () {
      for (final abi in [Abi.linuxX64, Abi.linuxArm64]) {
        expect(read(abi, memInfo: _memInfo, status: _status, ios: 1), (
          bytes: 2 << 30,
          source: 'MemAvailable in /proc/meminfo',
        ));
        expect(read(abi), isNull, reason: 'unreadable /proc/meminfo');
      }
    });

    group('on Android', () {
      String memInfo({required int totalKib, int? availableKib}) =>
          'MemTotal:       $totalKib kB\n'
          'MemFree:          100000 kB\n'
          '${availableKib == null ? '' : 'MemAvailable:   $availableKib kB\n'}';

      test('uses half of MemTotal less the app when that is larger', () {
        // A 6 GB phone: 5.26 GiB MemTotal, 1.70 GiB MemAvailable, 300 MiB
        // in the app.
        expect(
          read(
            Abi.androidArm64,
            memInfo: memInfo(totalKib: 5515000, availableKib: 1782579),
            status: _status,
          ),
          (
            bytes: 5515000 * 1024 ~/ 2 - (300 << 20),
            source: "half of MemTotal in /proc/meminfo less the app's memory",
          ),
        );
      });

      test('uses MemAvailable when that is larger', () {
        expect(
          read(
            Abi.androidArm64,
            memInfo: memInfo(totalKib: 15926000, availableKib: 9646000),
            status: _status,
          ),
          (bytes: 9646000 * 1024, source: 'MemAvailable in /proc/meminfo'),
        );
      });

      test('subtracts memory the app already holds, swapped or not', () {
        int? budget(String status) => read(
          Abi.androidArm64,
          memInfo: memInfo(totalKib: 8 << 20, availableKib: 1 << 20),
          status: status,
        )?.bytes;
        expect(budget('VmRSS:\t 2097152 kB\n'), 2 << 30);
        expect(budget('VmRSS:\t 1048576 kB\nVmSwap:\t 1048576 kB\n'), 2 << 30);
      });

      test("reads the app's memory from /proc/self/status by default", () {
        final budget = readStableDiffusionMemoryBudget(
          abi: Abi.androidArm64,
          readMemInfo: () => 'MemTotal:  1073741824 kB\nMemAvailable:  1 kB\n',
        );
        final status = File('/proc/self/status').readAsStringSync();
        final own =
            parseProcMemoryBytes(status, 'VmRSS')! +
            (parseProcMemoryBytes(status, 'VmSwap') ?? 0);
        expect(
          budget?.source,
          "half of MemTotal in /proc/meminfo less the app's memory",
        );
        // The process grows a little between the two reads.
        expect(budget!.bytes, closeTo((1 << 39) - own, 64 << 20));
      }, testOn: 'linux');

      test('falls back to MemAvailable without MemTotal or VmRSS', () {
        expect(read(Abi.androidArm64, memInfo: _memInfo), (
          bytes: 2 << 30,
          source: 'MemAvailable in /proc/meminfo',
        ), reason: 'unreadable /proc/self/status');
        expect(
          read(
            Abi.androidArm64,
            memInfo: 'MemAvailable:    2097152 kB\n',
            status: _status,
          ),
          (bytes: 2 << 30, source: 'MemAvailable in /proc/meminfo'),
        );
        expect(read(Abi.androidArm64, status: _status), isNull);
      });

      test('uses half of MemTotal without MemAvailable', () {
        expect(
          read(
            Abi.androidArm64,
            memInfo: memInfo(totalKib: 4 << 20),
            status: _status,
          )?.bytes,
          (2 << 30) - (300 << 20),
        );
      });
    });

    test("uses the app's remaining memory limit on iOS", () {
      expect(read(Abi.iosArm64, memInfo: _memInfo, ios: 3 << 30, macos: 1), (
        bytes: 3 << 30,
        source: "the app's remaining iOS memory limit",
      ));
      expect(read(Abi.iosArm64, ios: 0), isNull);
    });

    test('uses physical memory on macOS', () {
      expect(read(Abi.macosArm64, ios: 1, macos: 64 << 30), (
        bytes: 64 << 30,
        source: 'physical memory',
      ));
    });

    test("caps Metal on macOS at the GPU's recommended working set", () {
      expect(
        read(
          Abi.macosArm64,
          macos: 16 << 30,
          metal: 11 << 30,
          device: ImageGenerationComputeDevice.metal,
        ),
        (bytes: 11 << 30, source: "Metal's recommended GPU working set"),
      );
      for (final metal in [null, 0, 20 << 30]) {
        expect(
          read(
            Abi.macosArm64,
            macos: 16 << 30,
            metal: metal,
            device: ImageGenerationComputeDevice.metal,
          ),
          (bytes: 16 << 30, source: 'physical memory'),
          reason: 'working set $metal',
        );
      }
      expect(
        read(
          Abi.macosArm64,
          macos: 16 << 30,
          metal: 11 << 30,
          device: ImageGenerationComputeDevice.cpu,
        ),
        (bytes: 16 << 30, source: 'physical memory'),
      );
      expect(
        read(
          Abi.iosArm64,
          ios: 3 << 30,
          metal: 1 << 30,
          device: ImageGenerationComputeDevice.metal,
        ),
        (bytes: 3 << 30, source: "the app's remaining iOS memory limit"),
      );
    });

    test('reports nothing for GPUs whose device memory is unknown', () {
      for (final abi in [Abi.linuxX64, Abi.macosArm64, Abi.windowsX64]) {
        expect(
          read(
            abi,
            memInfo: _memInfo,
            macos: 64 << 30,
            metal: 48 << 30,
            device: ImageGenerationComputeDevice.otherGpu,
          ),
          isNull,
        );
      }
    });

    test('reports nothing on Windows', () {
      expect(read(Abi.windowsX64, memInfo: _memInfo, ios: 1, macos: 1), isNull);
    });

    test('reads the host', () {
      final budget = readStableDiffusionMemoryBudget();
      if (Platform.isMacOS || Platform.isLinux) {
        expect(budget!.bytes, greaterThan(1 << 30));
      }
    });

    test(
      'reads the exact Metal working set independently reported by Swift',
      () async {
        final cache = await Directory.systemTemp.createTemp('llamadart-metal-');
        addTearDown(() => cache.delete(recursive: true));
        final reference = await executeCommand('/usr/bin/xcrun', [
          'swift',
          '-module-cache-path',
          cache.path,
          'test/support/metal_working_set.swift',
        ], timeout: const Duration(seconds: 45));
        expect(reference.code, 0, reason: reference.error);
        final workingSet = int.parse(reference.output.trim());
        if (workingSet == 0) {
          // A headless macOS host may have no Metal device. The cap then falls
          // back to physical memory rather than claiming a device reading.
          expect(
            readStableDiffusionMemoryBudget(
              device: ImageGenerationComputeDevice.metal,
            ),
            readStableDiffusionMemoryBudget(),
          );
          return;
        }
        // Make physical memory larger than the independently read working set
        // so a wrong selector or altered value cannot pass a range assertion.
        expect(
          readStableDiffusionMemoryBudget(
            device: ImageGenerationComputeDevice.metal,
            macosPhysicalMemory: () => workingSet + 1,
          ),
          (bytes: workingSet, source: "Metal's recommended GPU working set"),
        );
      },
      skip: Platform.isMacOS ? false : 'macOS only',
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('readStableDiffusionGpuMemory', () {
    late FakeStableDiffusionRuntime runtime;

    setUp(() => runtime = FakeStableDiffusionRuntime());

    tearDown(() => runtime.close());

    List<StableDiffusionGpuMemory>? read({
      LlamaLogLevel logLevel = LlamaLogLevel.none,
      String? vulkanDevice,
    }) => readStableDiffusionGpuMemory(
      resolveCalls: runtime.resolver,
      logLevel: logLevel,
      environment: (name) => name == 'SD_VK_DEVICE' ? vulkanDevice : null,
    );

    test('counts the GPUs and asks each one by its index, after the recorder '
        'is registered at the log level', () async {
      runtime.gpus = [
        (total: 4 * _gib, free: 3 * _gib, integrated: false, status: 0),
        (total: 24 * _gib, free: 21 * _gib, integrated: false, status: 0),
        (total: 16 * _gib, free: 12 * _gib, integrated: true, status: 0),
      ];

      final memory = read(logLevel: LlamaLogLevel.warn);
      await runtime.flush();

      expect(memory, [
        (
          name: 'Vulkan0 (Fake GPU 0)',
          totalBytes: 4 * _gib,
          freeBytes: 3 * _gib,
          integrated: false,
        ),
        (
          name: 'Vulkan1 (Fake GPU 1)',
          totalBytes: 24 * _gib,
          freeBytes: 21 * _gib,
          integrated: false,
        ),
        (
          name: 'Vulkan2 (Fake GPU 2)',
          totalBytes: 16 * _gib,
          freeBytes: 12 * _gib,
          integrated: true,
        ),
      ]);
      expect(runtime.calls('caller'), [
        'sd_dart_log_enable',
        'sd_dart_log_set_level:3',
        'sd_dart_gpu_device_count',
        'sd_dart_gpu_device_memory:0',
        'sd_dart_gpu_device_memory:1',
        'sd_dart_gpu_device_memory:2',
      ]);
    });

    test(
      'is null without a GPU backend or a GPU, and asks no device',
      () async {
        for (final status in [-2, 0]) {
          runtime.gpuCountStatus = status;

          expect(read(), isNull, reason: '$status');
        }
        await runtime.flush();
        expect(
          runtime.calls('caller').where((call) => call.contains('memory')),
          isEmpty,
        );
      },
    );

    test('is null when one of the GPUs does not answer with its memory: '
        'memory unavailable, no device, an invalid argument', () {
      const known = (
        total: 8 * _gib,
        free: 6 * _gib,
        integrated: false,
        status: 0,
      );
      for (final status in [-1, -3, -4]) {
        final failing = (
          total: 8 * _gib,
          free: _gib,
          integrated: false,
          status: status,
        );
        for (final devices in [
          [failing],
          [known, failing],
          [failing, known],
        ]) {
          runtime.gpus = devices;

          expect(read(), isNull, reason: '$status of ${devices.length}');
        }
      }
    });

    test('a runtime older than the queries is not asked', () async {
      runtime
        ..olderRelease = true
        ..setGpuMemory(total: 8 * _gib, free: _gib);

      expect(read(), isNull);
      await runtime.flush();
      expect(runtime.calls('caller'), isEmpty);
    });

    test('is null without a runtime', () {
      expect(readStableDiffusionGpuMemory(resolveCalls: () => null), isNull);
    });

    test('SD_VK_DEVICE, which can make the runtime pick the device, skips '
        'the queries', () async {
      runtime.setGpuMemory(total: 8 * _gib, free: _gib);

      expect(read(vulkanDevice: '1'), isNull);
      await runtime.flush();
      expect(runtime.calls('caller'), isEmpty);
      expect(read(), hasLength(1));
    });
  });

  group('stableDiffusionGpuMemoryLimits', () {
    const host = (bytes: 5 * _gib, source: 'MemAvailable in /proc/meminfo');
    const noLimits = (refuse: null, slower: null);

    ImageGenerationMemoryLimits limits(
      List<StableDiffusionGpuMemory>? gpus, {
      ImageGenerationMemoryBudget? hostBudget = host,
      bool runtimePicksGpu = true,
    }) => stableDiffusionGpuMemoryLimits(
      gpus,
      runtimePicksGpu: runtimePicksGpu,
      hostBudget: () => hostBudget,
    );

    StableDiffusionGpuMemory gpu({
      required int total,
      required int free,
      bool integrated = false,
      String name = 'Vulkan0 (NVIDIA L4)',
    }) => (
      name: name,
      totalBytes: total,
      freeBytes: free,
      integrated: integrated,
    );

    test('a discrete GPU whose driver reports a budget is slower above its '
        'free memory, and refuses above that plus host memory', () {
      for (final runtimePicksGpu in [true, false]) {
        expect(
          limits([
            gpu(total: 24 * _gib, free: 9 * _gib),
          ], runtimePicksGpu: runtimePicksGpu),
          (
            refuse: (
              bytes: 14 * _gib,
              source:
                  '9.00 GiB of GPU memory and 5.00 GiB of system memory: free '
                  'GPU memory of Vulkan0 (NVIDIA L4), out of 24.0 GiB; '
                  'MemAvailable in /proc/meminfo',
            ),
            slower: (
              bytes: 9 * _gib,
              source: 'free GPU memory of Vulkan0 (NVIDIA L4), out of 24.0 GiB',
            ),
          ),
        );
      }
      for (final free in [8 * _gib - 1, 1]) {
        final result = limits([gpu(total: 8 * _gib, free: free)]);
        expect(result.slower?.bytes, free);
        expect(result.refuse?.bytes, free + 5 * _gib);
      }
    });

    test('a discrete GPU that reports its total as free uses its total '
        'memory and says that free memory is unknown', () {
      expect(limits([gpu(total: 8 * _gib, free: 8 * _gib)]), (
        refuse: (
          bytes: 13 * _gib,
          source:
              '8.00 GiB of GPU memory and 5.00 GiB of system memory: the '
              'GPU memory of Vulkan0 (NVIDIA L4), whose driver does not '
              'report how much of it is free; MemAvailable in '
              '/proc/meminfo',
        ),
        slower: (
          bytes: 8 * _gib,
          source:
              'the GPU memory of Vulkan0 (NVIDIA L4), whose driver does '
              'not report how much of it is free',
        ),
      ));
    });

    test('a discrete GPU over its budget, which reports 0 free, has no free '
        'memory: any model is slower, and refused above host memory', () {
      expect(limits([gpu(total: 8 * _gib, free: 0)]), (
        refuse: (
          bytes: 5 * _gib,
          source:
              '0.00 GiB of GPU memory and 5.00 GiB of system memory: free '
              'GPU memory of Vulkan0 (NVIDIA L4), out of 8.00 GiB; '
              'MemAvailable in /proc/meminfo',
        ),
        slower: (
          bytes: 0,
          source: 'free GPU memory of Vulkan0 (NVIDIA L4), out of 8.00 GiB',
        ),
      ));
      expect(limits([gpu(total: 8 * _gib, free: 0)], hostBudget: null), (
        refuse: null,
        slower: (
          bytes: 0,
          source: 'free GPU memory of Vulkan0 (NVIDIA L4), out of 8.00 GiB',
        ),
      ));
    });

    test('a discrete GPU where host memory is not read, as on Windows, is '
        'slower above its figure and refuses nothing', () {
      expect(
        limits([gpu(total: 24 * _gib, free: 9 * _gib)], hostBudget: null),
        (
          refuse: null,
          slower: (
            bytes: 9 * _gib,
            source: 'free GPU memory of Vulkan0 (NVIDIA L4), out of 24.0 GiB',
          ),
        ),
      );
      expect(limits([gpu(total: 8 * _gib, free: 8 * _gib)], hostBudget: null), (
        refuse: null,
        slower: (
          bytes: 8 * _gib,
          source:
              'the GPU memory of Vulkan0 (NVIDIA L4), whose driver does '
              'not report how much of it is free',
        ),
      ));
    });

    group('with several discrete GPUs', () {
      // A 4 GiB GPU listed before a 24 GiB one.
      final small = gpu(
        total: 4 * _gib,
        free: 4 * _gib,
        name: 'Vulkan0 (GTX 1650)',
      );
      final large = gpu(
        total: 24 * _gib,
        free: 22 * _gib,
        name: 'Vulkan1 (RTX 4090)',
      );
      const smallSource =
          'the GPU memory of Vulkan0 (GTX 1650), whose driver does not '
          'report how much of it is free';
      const largeSource =
          'free GPU memory of Vulkan1 (RTX 4090), out of 24.0 GiB';
      const sum =
          '26.0 GiB of GPU memory on 2 GPUs and 5.00 GiB of system memory: '
          '4.00 GiB, $smallSource; 22.0 GiB, $largeSource; MemAvailable in '
          '/proc/meminfo';

      test('with no backend named, a model is slower above the GPU with the '
          'most memory, wherever it is listed, and refused above all of '
          'them plus host memory', () {
        for (final gpus in [
          [small, large],
          [large, small],
        ]) {
          final result = limits(gpus);

          expect(result.slower, (bytes: 22 * _gib, source: largeSource));
          expect(result.refuse?.bytes, 31 * _gib);
        }
        expect(limits([small, large]).refuse?.source, sum);
      });

      test('a 16.8 GiB model on a 4 GiB GPU listed before a 24 GiB one, '
          'with 9 GiB of host memory, neither is refused nor slower', () {
        const estimate = 168 * _gib ~/ 10;
        final result = limits(
          [
            gpu(total: 4 * _gib, free: 4 * _gib, name: 'Vulkan0'),
            gpu(total: 24 * _gib, free: 24 * _gib, name: 'Vulkan1'),
          ],
          hostBudget: (bytes: 9 * _gib, source: 'MemAvailable'),
        );

        expect(result.refuse!.bytes, 37 * _gib);
        expect(result.refuse!.bytes, greaterThan(estimate));
        expect(result.slower!.bytes, 24 * _gib);
        expect(result.slower!.source, contains('Vulkan1'));
      });

      test('the backend gpu is the first discrete GPU: a model is slower '
          'above that one, and still refused above all of them plus host '
          'memory', () {
        final result = limits([small, large], runtimePicksGpu: false);

        expect(result.slower, (bytes: 4 * _gib, source: smallSource));
        expect(result.refuse, (bytes: 31 * _gib, source: sum));
        expect(
          limits([large, small], runtimePicksGpu: false).slower?.bytes,
          22 * _gib,
        );
      });

      test('of two GPUs with the same figure the first one computes', () {
        final first = gpu(total: 8 * _gib, free: 6 * _gib, name: 'Vulkan0');
        final second = gpu(total: 12 * _gib, free: 6 * _gib, name: 'Vulkan1');

        expect(
          limits([first, second]).slower?.source,
          'free GPU memory of Vulkan0, out of 8.00 GiB',
        );
      });

      test('where host memory is not read nothing is refused', () {
        final result = limits([small, large], hostBudget: null);

        expect(result.refuse, isNull);
        expect(result.slower?.bytes, 22 * _gib);
      });

      test('an integrated GPU beside discrete ones adds nothing: its memory '
          'is host memory', () {
        final integrated = gpu(
          total: 64 * _gib,
          free: 60 * _gib,
          integrated: true,
          name: 'Vulkan2 (Intel UHD)',
        );
        for (final gpus in [
          [integrated, small, large],
          [small, large, integrated],
        ]) {
          for (final runtimePicksGpu in [true, false]) {
            final result = limits(gpus, runtimePicksGpu: runtimePicksGpu);

            expect(result.refuse, (bytes: 31 * _gib, source: sum));
            expect(result.slower?.bytes, (runtimePicksGpu ? 22 : 4) * _gib);
          }
        }
      });
    });

    test('an integrated GPU refuses above the host figure, never its own, '
        'and has nothing slower', () {
      for (final (total, free) in [(64 * _gib, 60 * _gib), (2 * _gib, _gib)]) {
        for (final runtimePicksGpu in [true, false]) {
          expect(
            limits([
              gpu(total: total, free: free, integrated: true),
            ], runtimePicksGpu: runtimePicksGpu),
            (
              refuse: (
                bytes: 5 * _gib,
                source:
                    'MemAvailable in /proc/meminfo; Vulkan0 (NVIDIA L4) is an '
                    'integrated GPU, which uses host memory',
              ),
              slower: null,
            ),
          );
        }
      }
    });

    test('an integrated GPU has no limit where host memory is not read', () {
      expect(
        limits([
          gpu(total: 16 * _gib, free: 8 * _gib, integrated: true),
        ], hostBudget: null),
        noLimits,
      );
    });

    test('unknown memory has no limit, and the host is not asked', () {
      ImageGenerationMemoryBudget? unasked() => fail('asked the host');

      for (final gpus in [
        null,
        <StableDiffusionGpuMemory>[],
        [gpu(total: 0, free: 0)],
        [gpu(total: 8 * _gib, free: _gib), gpu(total: 0, free: 0)],
      ]) {
        expect(
          stableDiffusionGpuMemoryLimits(
            gpus,
            runtimePicksGpu: true,
            hostBudget: unasked,
          ),
          noLimits,
        );
      }
    });
  });

  test('readStableDiffusionFileRange reads a range and stops at the end of '
      'the file', () async {
    final directory = await Directory.systemTemp.createTemp('llamadart-sd-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/header.gguf')
      ..writeAsBytesSync(List.generate(10, (i) => i));

    expect(await readStableDiffusionFileRange(file.path, 2, 3), [2, 3, 4]);
    expect(await readStableDiffusionFileRange(file.path, 8, 64), [8, 9]);
    expect(await readStableDiffusionFileRange(file.path, 20, 4), isEmpty);
  });

  group('stableDiffusionFileSize', () {
    test('sizes a file and ignores directories and missing paths', () async {
      final directory = await Directory.systemTemp.createTemp('llamadart-sd-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/taesd.safetensors')
        ..writeAsBytesSync(List.filled(42, 1));

      expect(stableDiffusionFileSize(file.path), 42);
      expect(stableDiffusionFileSize(directory.path), isNull);
      expect(stableDiffusionFileSize('${file.path}.missing'), isNull);
    });

    test('sizes a file whose path holds %, # and ? literally', () async {
      final directory = await Directory.systemTemp.createTemp('llamadart-sd-');
      addTearDown(() => directory.delete(recursive: true));
      final name = Platform.isWindows ? 'a#b%zz%25' : 'a#b?c%zz%25';
      final file = File('${directory.path}/100% $name/sd 100%.gguf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(7, 1));

      expect(stableDiffusionFileSize(file.path), 7);
    });
  });
}
