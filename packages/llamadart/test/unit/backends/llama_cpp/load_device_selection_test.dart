@TestOn('vm')
library;

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:test/test.dart';

final _cpuType = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value;
final _accelType = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value;
final _gpuType = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final _igpuType = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;

const _none = 0;
const _layer = 1;
const _row = 2;
const _tensor = 3;

const _vulkan11 = 1 << 22 | 1 << 12;
const _vulkan13 = 1 << 22 | 3 << 12;

GgmlDeviceEntry _device(
  String name, {
  int? type,
  String? registry,
  String? deviceId,
  String description = '',
}) => GgmlDeviceEntry(
  name: name,
  type: type ?? _gpuType,
  registry: registry ?? name.replaceAll(RegExp(r'\d+$'), ''),
  description: description,
  deviceId: deviceId,
);

final _cpu = _device('CPU', type: _cpuType);
final _blas = _device('BLAS', type: _accelType);

// A Vulkan device as the facts report it: its Vulkan device name, which is
// the description of the ggml device, and the driver API version.
VulkanDeviceFacts _fact(
  String name,
  int apiVersion, {
  bool integrated = false,
  int instanceApiVersion = _vulkan13,
}) => VulkanDeviceFacts(
  name: name,
  deviceType: integrated ? 1 : 2,
  instanceApiVersion: instanceApiVersion,
  apiVersion: apiVersion,
  subgroupSize: 32,
);

VulkanDeviceProbe Function() _facts(List<VulkanDeviceFacts> facts) =>
    () => VulkanDeviceProbe.devices(facts);

void main() {
  test('split modes match the llama_split_mode values', () {
    expect(llama_split_mode.LLAMA_SPLIT_MODE_NONE.value, _none);
    expect(llama_split_mode.LLAMA_SPLIT_MODE_LAYER.value, _layer);
    expect(llama_split_mode.LLAMA_SPLIT_MODE_ROW.value, _row);
    expect(llama_split_mode.LLAMA_SPLIT_MODE_TENSOR.value, _tensor);
  });

  group('selectModelDevices', () {
    List<String> select(
      List<GgmlDeviceEntry> registered, {
      List<GgmlDeviceEntry>? listed,
      int splitMode = _layer,
      int mainGpu = 0,
    }) => [
      for (final device in selectModelDevices(
        registered: registered,
        listed: listed,
        splitMode: splitMode,
        mainGpu: mainGpu,
      ))
        device.name,
    ];

    test('uses the listed devices as they are', () {
      final listed = [_device('Vulkan1', type: _igpuType), _device('Vulkan0')];

      expect(select([_cpu, _device('CUDA0')], listed: listed), [
        'Vulkan1',
        'Vulkan0',
      ]);
    });

    test('without a list takes the discrete GPUs and skips CPU and '
        'accelerator devices', () {
      expect(select([_cpu, _blas, _device('CUDA0'), _device('Vulkan0')]), [
        'CUDA0',
        'Vulkan0',
      ]);
    });

    test('takes integrated GPUs only when there is no discrete GPU, and '
        'then those of one backend', () {
      final igpu = _device('Vulkan1', type: _igpuType);

      expect(select([_cpu, _device('Vulkan0'), igpu]), ['Vulkan0']);
      expect(select([_cpu, igpu]), ['Vulkan1']);
      expect(
        select([
          igpu,
          _device('OpenCL0', type: _igpuType),
          _device('Vulkan2', type: _igpuType),
        ]),
        ['Vulkan1', 'Vulkan2'],
        reason: 'an integrated GPU of another backend is skipped',
      );
      expect(select([igpu, _device('Vulkan2', type: _igpuType)]), [
        'Vulkan1',
        'Vulkan2',
      ]);
    });

    test('skips a discrete GPU whose device id an earlier one has', () {
      expect(
        select([
          _device('CUDA0', deviceId: '0000:01:00.0'),
          _device('Vulkan0', deviceId: '0000:01:00.0'),
          _device('Vulkan1', deviceId: '0000:02:00.0'),
          _device('Vulkan2'),
          _device('Vulkan3'),
        ]),
        ['CUDA0', 'Vulkan1', 'Vulkan2', 'Vulkan3'],
      );
    });

    test('puts RPC servers first, and they do not count as discrete '
        'GPUs', () {
      final igpu = _device('Vulkan0', type: _igpuType);

      expect(select([igpu, _device('RPC0')]), ['RPC0', 'Vulkan0']);
      expect(select([_device('CUDA0'), igpu, _device('RPC0')]), [
        'RPC0',
        'CUDA0',
      ]);
    });

    test('tensor split mode takes every device that is not a CPU or an '
        'accelerator', () {
      expect(
        select([
          _cpu,
          _blas,
          _device('Vulkan0'),
          _device('Vulkan1', type: _igpuType),
        ], splitMode: _tensor),
        ['Vulkan0', 'Vulkan1'],
      );
    });

    test('single-device mode keeps the device mainGpu indexes, or none', () {
      final registered = [_device('Vulkan0'), _device('Vulkan1')];

      expect(select(registered, splitMode: _none), ['Vulkan0']);
      expect(select(registered, splitMode: _none, mainGpu: 1), ['Vulkan1']);
      expect(select(registered, splitMode: _none, mainGpu: 2), isEmpty);
      expect(select(registered, splitMode: _none, mainGpu: -1), isEmpty);
      expect(
        select(const [], listed: registered, splitMode: _none, mainGpu: 1),
        ['Vulkan1'],
      );
      expect(select([_cpu], splitMode: _none), isEmpty);
    });
  });

  group('selectsNoGpuDevice', () {
    test('single-device mode with a negative mainGpu selects CPU', () {
      for (final mainGpu in [-1, -2]) {
        expect(selectsNoGpuDevice(splitMode: _none, mainGpu: mainGpu), isTrue);
      }
    });

    test('single-device mode with mainGpu zero retains GPU selection', () {
      expect(selectsNoGpuDevice(splitMode: _none, mainGpu: 0), isFalse);
    });

    test('layer, row and tensor modes do not prune a negative mainGpu', () {
      for (final splitMode in [_layer, 2, _tensor]) {
        expect(selectsNoGpuDevice(splitMode: splitMode, mainGpu: -1), isFalse);
      }
    });
  });

  group('vulkanFactsOf', () {
    final rtx = _device('Vulkan0', description: 'RTX 4090');

    test('finds the facts by the Vulkan device name and kind, not by '
        'position', () {
      final facts = [
        _fact('UHD Graphics 630', _vulkan11, integrated: true),
        _fact('RTX 4090', _vulkan13),
      ];

      expect(vulkanFactsOf(rtx, facts), same(facts[1]));
      expect(
        vulkanFactsOf(
          _device('Vulkan1', type: _igpuType, description: 'UHD Graphics 630'),
          facts,
        ),
        same(facts[0]),
      );
    });

    test('knows nothing of a device without facts of its name and kind', () {
      expect(vulkanFactsOf(rtx, [_fact('RX 7900', _vulkan11)]), isNull);
      expect(
        vulkanFactsOf(rtx, [_fact('RTX 4090', _vulkan11, integrated: true)]),
        isNull,
        reason: 'the same name on an integrated GPU is another device',
      );
      expect(vulkanFactsOf(rtx, const []), isNull);
      expect(
        vulkanFactsOf(_device('Vulkan0'), [_fact('', _vulkan11)]),
        isNull,
        reason: 'a device whose description was not read',
      );
      expect(
        vulkanFactsOf(_device('CUDA0', description: 'RTX 4090'), [
          _fact('RTX 4090', _vulkan11),
        ]),
        isNull,
        reason: 'not a ggml-vulkan device',
      );
    });

    test('takes identical devices together when they agree, and knows '
        'nothing when they do not', () {
      expect(
        vulkanFactsOf(rtx, [
          _fact('RTX 4090', _vulkan13),
          _fact('RTX 4090', _vulkan13),
        ])?.meetsVulkan12,
        isTrue,
      );
      expect(
        vulkanFactsOf(rtx, [
          _fact('RTX 4090', _vulkan11),
          _fact('RTX 4090', _vulkan11),
        ])?.meetsVulkan12,
        isFalse,
      );
      expect(
        vulkanFactsOf(rtx, [
          _fact('RTX 4090', _vulkan13),
          _fact('RTX 4090', _vulkan11),
        ]),
        isNull,
      );
    });
  });

  group('resolveVulkanLoadDecision', () {
    late int registryReads;
    late int probeReads;

    setUp(() {
      registryReads = 0;
      probeReads = 0;
    });

    VulkanLoadDecision decide(
      List<GgmlDeviceEntry> registered,
      VulkanDeviceProbe Function() probe, {
      String? backend,
      bool usesGpu = true,
      int splitMode = _layer,
      int mainGpu = 0,
      bool isAndroid = false,
    }) => resolveVulkanLoadDecision(
      usesGpu: usesGpu,
      isAndroid: isAndroid,
      backendRegistry: backend,
      splitMode: splitMode,
      mainGpu: mainGpu,
      registered: () {
        registryReads++;
        return registered;
      },
      probe: () {
        probeReads++;
        return probe();
      },
    );

    Matcher unchanged() => isA<VulkanLoadDecision>()
        .having((d) => d.unsupported, 'unsupported', isNull)
        .having((d) => d.devices, 'devices', isNull)
        .having((d) => d.refused, 'refused', isFalse);

    Matcher without(String excluded, List<String> usable) =>
        isA<VulkanLoadDecision>()
            .having((d) => d.unsupported, 'unsupported', contains(excluded))
            .having(
              (d) => [for (final device in d.devices ?? const []) device.name],
              'devices',
              usable,
            )
            .having((d) => d.refused, 'refused', isFalse);

    Matcher refused(String device) => isA<VulkanLoadDecision>()
        .having((d) => d.unsupported, 'unsupported', contains(device))
        .having((d) => d.devices, 'devices', isNull)
        .having((d) => d.refused, 'refused', isTrue);

    final rtx = _device(
      'Vulkan0',
      deviceId: '0000:01:00.0',
      description: 'RTX 4090',
    );
    final uhd = _device(
      'Vulkan1',
      type: _igpuType,
      description: 'UHD Graphics 630',
    );
    final cuda = _device('CUDA0', deviceId: '0000:01:00.0');
    final rtxOk = _fact('RTX 4090', _vulkan13);
    final uhdOld = _fact('UHD Graphics 630', _vulkan11, integrated: true);
    final maliOld = _fact('Mali-G68', _vulkan11);
    final mali = _device('Vulkan0', description: 'Mali-G68');

    test(
      'refuses Android GPU loads when the affected driver is registered',
      () {
        final adreno = _device('Vulkan0', description: 'Adreno (TM) 750');
        const bad = VulkanDeviceFacts(
          name: 'Adreno (TM) 750',
          deviceType: 2,
          instanceApiVersion: _vulkan13,
          apiVersion: _vulkan13,
          subgroupSize: 64,
          vendorId: 0x5143,
          driverVersion: 2150604839,
        );
        expect(
          decide([adreno], _facts([bad]), isAndroid: true),
          refused('driver 2150604839'),
        );
        expect(decide([adreno], _facts([bad])), unchanged());
        expect(
          decide([adreno], _facts([bad]), isAndroid: true, usesGpu: false),
          unchanged(),
        );
        expect(
          decide([adreno, cuda], _facts([bad]), isAndroid: true),
          refused('driver 2150604839'),
        );
        expect(
          decide(
            [adreno, rtx],
            _facts([bad, rtxOk]),
            isAndroid: true,
            splitMode: _none,
            mainGpu: 1,
          ),
          refused('driver 2150604839'),
        );
        final newer = VulkanDeviceFacts(
          name: bad.name,
          deviceType: bad.deviceType,
          instanceApiVersion: bad.instanceApiVersion,
          apiVersion: bad.apiVersion,
          subgroupSize: bad.subgroupSize,
          vendorId: bad.vendorId,
          driverVersion: bad.driverVersion + 1,
        );
        expect(decide([adreno], _facts([newer]), isAndroid: true), unchanged());
        expect(
          decide([adreno], _facts([bad, newer]), isAndroid: true),
          refused('driver 2150604839'),
        );
        expect(
          decide(
            [adreno],
            () => const VulkanDeviceProbe.unavailable('missing'),
            isAndroid: true,
          ),
          unchanged(),
        );
      },
    );

    test('a load that offloads nothing reads neither the registry nor the '
        'facts', () {
      expect(decide([mali], _facts([maliOld]), usesGpu: false), unchanged());
      expect((registryReads, probeReads), (0, 0));
    });

    test('refuses when the only selected device is below Vulkan 1.2, naming '
        'it and its versions', () {
      final decision = decide([_cpu, mali], _facts([maliOld]));

      expect(decision, refused('"Mali-G68" (Vulkan0)'));
      expect(
        decision.unsupported,
        "llama.cpp's Vulkan backend needs Vulkan 1.2 or later from both the "
        'Vulkan loader and the GPU driver, and "Mali-G68" (Vulkan0) reports '
        'driver API 1.1 with loader API 1.3',
      );
      expect(
        decide([
          _device('Vulkan0', type: _igpuType, description: 'UHD Graphics 630'),
        ], _facts([uhdOld])),
        refused('"UHD Graphics 630" (Vulkan0)'),
        reason: 'an integrated GPU is selected when it is the only GPU',
      );
    });

    test('a capable discrete GPU beside an integrated GPU on an old driver '
        'changes nothing: the integrated one is not selected', () {
      for (final registered in [
        [_cpu, rtx, uhd],
        [_cpu, cuda, rtx, uhd],
      ]) {
        expect(decide(registered, _facts([rtxOk, uhdOld])), unchanged());
      }
    });

    test('a CUDA GPU beside an old Vulkan device does not read the Vulkan '
        'facts when llama.cpp would not select that device', () {
      // The same physical GPU through Vulkan, and an integrated GPU.
      expect(
        decide([cuda, rtx, uhd], () => fail('no Vulkan device is selected')),
        unchanged(),
      );
      expect(probeReads, 0);
    });

    test('leaves out a selected device below Vulkan 1.2 when usable devices '
        'remain', () {
      expect(
        decide([
          _device('CUDA0', deviceId: '0000:01:00.0'),
          _device('Vulkan0', deviceId: '0000:02:00.0', description: 'Mali-G68'),
        ], _facts([maliOld])),
        without('"Mali-G68" (Vulkan0)', ['CUDA0']),
      );
      expect(
        decide(
          [
            _device('Vulkan0', description: 'RTX 4090'),
            _device('Vulkan1', description: 'GTX 660'),
            _device('Vulkan2', description: 'RX 7900'),
          ],
          _facts([
            rtxOk,
            _fact('GTX 660', _vulkan11),
            _fact('RX 7900', _vulkan13),
          ]),
        ),
        without('"GTX 660" (Vulkan1)', ['Vulkan0', 'Vulkan2']),
      );
    });

    // ggml-vulkan and the facts can list different devices: whether ggml
    // registers a device below Vulkan 1.2 is undefined.
    for (final backend in [null, 'Vulkan']) {
      final how = backend == null ? "llama.cpp's selection" : 'explicit Vulkan';

      test('$how: facts that list a device ggml did not register do not '
          'shift onto the registered ones', () {
        final a = _device('Vulkan0', description: 'RTX 4090');
        final b = _device('Vulkan1', description: 'RX 7900');
        final bOk = _fact('RX 7900', _vulkan13);
        final old = _fact('GTX 660', _vulkan11);

        expect(
          decide([a], _facts([uhdOld, rtxOk]), backend: backend),
          unchanged(),
          reason: 'Vulkan0 is the RTX, not the first entry of the facts',
        );
        for (final facts in [
          [old, rtxOk, bOk],
          [rtxOk, bOk, old],
          [rtxOk, old, bOk],
        ]) {
          expect(
            decide([a, b], _facts(facts), backend: backend),
            unchanged(),
            reason: '${facts.map((fact) => fact.name)}',
          );
        }
      });

      test('$how: names the device that is below Vulkan 1.2, wherever its '
          'facts are listed', () {
        final onlyOld = _device('Vulkan0', description: 'GTX 660');

        expect(
          decide(
            [onlyOld],
            _facts([rtxOk, _fact('GTX 660', _vulkan11)]),
            backend: backend,
          ),
          refused('"GTX 660" (Vulkan0)'),
        );
      });

      test('$how: identical GPUs are judged together', () {
        final twins = [
          _device('Vulkan0', description: 'RTX 4090'),
          _device('Vulkan1', description: 'RTX 4090'),
        ];

        expect(
          decide(twins, _facts([rtxOk, rtxOk]), backend: backend),
          unchanged(),
        );
        expect(
          decide(
            twins,
            _facts([
              _fact('RTX 4090', _vulkan11),
              _fact('RTX 4090', _vulkan11),
            ]),
            backend: backend,
          ),
          refused('"RTX 4090" (Vulkan0)'),
        );
        expect(
          decide(
            twins,
            _facts([rtxOk, _fact('RTX 4090', _vulkan11)]),
            backend: backend,
          ),
          unchanged(),
          reason: 'which twin is on the old driver cannot be told',
        );
      });

      test('$how: a device without a facts entry is unknown, and the others '
          'are still judged', () {
        final a = _device('Vulkan0', description: 'GTX 660');
        final b = _device('Vulkan1', description: 'RX 7900');

        expect(
          decide(
            [a, b],
            _facts([_fact('GTX 660', _vulkan11)]),
            backend: backend,
          ),
          without('"GTX 660" (Vulkan0)', ['Vulkan1']),
        );
        expect(
          decide(
            [a, b],
            _facts([_fact('RX 7900', _vulkan13)]),
            backend: backend,
          ),
          unchanged(),
        );
        expect(decide([a, b], _facts(const []), backend: backend), unchanged());
      });
    }

    test('an explicit backend is judged by its own devices only', () {
      final oldVulkan = _device(
        'Vulkan0',
        deviceId: '0000:02:00.0',
        description: 'Mali-G68',
      );

      expect(
        decide(
          [cuda, oldVulkan],
          () => fail('CUDA lists no Vulkan device'),
          backend: 'CUDA',
        ),
        unchanged(),
      );
      expect(probeReads, 0);

      // The Vulkan backend lists every Vulkan device, integrated ones too.
      expect(
        decide([cuda, rtx, uhd], _facts([rtxOk, uhdOld]), backend: 'Vulkan'),
        without('"UHD Graphics 630" (Vulkan1)', ['Vulkan0']),
      );
      expect(
        decide(
          [cuda, rtx, uhd],
          _facts([_fact('RTX 4090', _vulkan11), uhdOld]),
          backend: 'vulkan',
        ),
        refused('"RTX 4090" (Vulkan0)'),
      );
    });

    test('an explicit backend without a registered device falls back to '
        "llama.cpp's own selection", () {
      expect(
        decide([mali], _facts([maliOld]), backend: 'CUDA'),
        refused('(Vulkan0)'),
      );
    });

    test('single-device mode judges the device mainGpu selects', () {
      final registered = [
        _device('Vulkan0', description: 'RTX 4090'),
        _device('Vulkan1', description: 'GTX 660'),
      ];
      final facts = _facts([rtxOk, _fact('GTX 660', _vulkan11)]);

      expect(decide(registered, facts, splitMode: _none), unchanged());
      expect(
        decide(registered, facts, splitMode: _none, mainGpu: 1),
        refused('"GTX 660" (Vulkan1)'),
      );
      expect(
        decide(registered, facts, splitMode: _none, mainGpu: 5),
        unchanged(),
        reason: 'llama.cpp rejects the load before it starts a device',
      );
    });

    test('tensor split mode judges every GPU, integrated ones included', () {
      expect(
        decide([rtx, uhd], _facts([rtxOk, uhdOld]), splitMode: _tensor),
        without('(Vulkan1)', ['Vulkan0']),
      );
    });

    test('unknown devices are not refused', () {
      expect(
        decide([mali], () => const VulkanDeviceProbe.unavailable('no loader')),
        unchanged(),
      );
      expect(
        decide([_device('Vulkan0')], _facts([maliOld])),
        unchanged(),
        reason: 'a device whose description was not read has no facts',
      );
      expect(
        decide([_device('Vulkan0', description: 'RTX 4090')], _facts([rtxOk])),
        unchanged(),
      );
    });

    test('a loader below Vulkan 1.2 counts like a driver below it', () {
      expect(
        decide(
          [_device('Vulkan0', description: 'Mali-G52')],
          _facts([_fact('Mali-G52', _vulkan13, instanceApiVersion: _vulkan11)]),
        ).unsupported,
        endsWith(
          '"Mali-G52" (Vulkan0) reports driver API 1.3 with loader API 1.1',
        ),
      );
    });
  });

  group('rowSplitUnsupportedReason', () {
    final sycl0 = _device('SYCL0');
    final sycl1 = _device('SYCL1');
    final vulkan0 = _device('Vulkan0');

    String? reason(
      List<GgmlDeviceEntry> devices, {
      int splitMode = _row,
      Set<String> withSplitBuffers = const {'SYCL'},
      List<String>? probed,
    }) => rowSplitUnsupportedReason(
      splitMode: splitMode,
      devices: devices,
      hasSplitBufferType: (device) {
        probed?.add(device.name);
        return withSplitBuffers.contains(device.registry);
      },
    );

    test('is null when every model device has split buffers', () {
      expect(reason([sycl0, sycl1]), isNull);
    });

    test('names the first model device whose backend has none', () {
      final probed = <String>[];

      expect(
        reason([sycl0, vulkan0, _device('Vulkan1')], probed: probed),
        allOf(contains('Vulkan0 (Vulkan)'), isNot(contains('Vulkan1'))),
      );
      expect(probed, ['SYCL0', 'Vulkan0']);
    });

    test('probes the CPU device of a list as llama.cpp does', () {
      expect(reason([_cpu]), contains('CPU (CPU)'));
    });

    test('names a device without a registry name on its own', () {
      expect(
        reason([_device('GPU0', registry: '')]),
        allOf(contains('GPU0'), isNot(contains('GPU0 ('))),
      );
    });

    test('is null without model devices, which llama.cpp never probes', () {
      expect(reason(const []), isNull);
    });

    test('probes nothing in another split mode', () {
      for (final mode in [_none, _layer, _tensor]) {
        final probed = <String>[];

        expect(reason([vulkan0], splitMode: mode, probed: probed), isNull);
        expect(probed, isEmpty);
      }
    });
  });
}
