@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:test/test.dart';

import '../../../../example/chat_app/integration_test/support/micro_batch_sweep_support.dart';

const _vulkan13 = 1 << 22 | 3 << 12;

VulkanDeviceFacts _facts(String name, int subgroupSize) => VulkanDeviceFacts(
  name: name,
  deviceType: 1,
  instanceApiVersion: _vulkan13,
  apiVersion: _vulkan13 | 283,
  subgroupSize: subgroupSize,
);

/// The debug records and the result of the service's own cap decision for
/// an Android runtime that registered [registered] Vulkan devices and whose
/// probe answers [probe]. Nothing native is loaded: the registry and the
/// probe are the injected ones.
({bool defect, List<String> debug}) _decide(
  VulkanDeviceProbe probe, {
  int registered = 1,
}) {
  final service = LlamaCppService(
    isAndroid: true,
    vulkanDeviceProbe: () => probe,
    registeredDevices: () => [
      for (var index = 0; index < registered; index++)
        GgmlDeviceEntry(name: 'Vulkan$index', type: 1, registry: 'Vulkan'),
    ],
  );
  final logger = LlamaLogger.instance;
  final level = logger.level;
  final debug = <String>[];
  logger
    ..setLevel(LlamaLogLevel.debug)
    ..setHandler((record) {
      if (record.level == LlamaLogLevel.debug) debug.add(record.message);
    });
  try {
    final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
    final defect =
        reflect(service)
                .invoke(
                  MirrorSystem.getSymbol(
                    '_androidVulkanHasSmallMatmulTileDefect',
                    owner,
                  ),
                  const [],
                )
                .reflectee
            as bool;
    return (defect: defect, debug: debug);
  } finally {
    logger
      ..setHandler(null)
      ..setLevel(level);
  }
}

/// The micro-batch sweep E2E of the chat app reads the cap decision out of
/// the line the service logs. These tests take that line from the service
/// itself, so rewording it there fails here instead of turning the E2E's
/// record into `not_logged`.
void main() {
  test('the sweep E2E reads the line the service logs for a capped '
      'device', () {
    final decided = _decide(
      VulkanDeviceProbe.devices([_facts('Mali-G715', 16)]),
    );

    expect(decided.defect, isTrue);
    final decision = parsePromptCapDecision(decided.debug.single)!;
    expect(
      decision.capTokens,
      LlamaCppService.androidVulkanPromptMicroBatchSize,
    );
    expect(decision.devices, [
      (
        name: 'Mali-G715',
        apiVersion: '1.3',
        loaderApiVersion: '1.3',
        subgroupSize: 16,
      ),
    ]);
  });

  test('the sweep E2E reads the line the service logs when it lifts the '
      'cap', () {
    final decided = _decide(
      VulkanDeviceProbe.devices([
        _facts('Adreno (TM) 750', 64),
        _facts('Odd "GPU"', 8),
      ]),
      registered: 2,
    );

    expect(decided.defect, isFalse);
    final decision = parsePromptCapDecision(decided.debug.single)!;
    expect(decision.capTokens, isNull);
    expect(
      [for (final device in decision.devices) device.name],
      ['Adreno (TM) 750', 'Odd "GPU"'],
    );
    expect(
      [for (final device in decision.devices) device.subgroupSize],
      [64, 8],
    );
  });

  test('the sweep E2E reads the line the service logs when the probe is '
      'unavailable', () {
    final decided = _decide(
      const VulkanDeviceProbe.unavailable('no Vulkan loader'),
    );

    expect(decided.defect, isTrue);
    final decision = parsePromptCapDecision(decided.debug.single)!;
    expect(
      decision.capTokens,
      LlamaCppService.androidVulkanPromptMicroBatchSize,
    );
    expect(decision.devices, isEmpty);
    expect(decision.detail, 'no Vulkan loader');
  });

  test('the service logs nothing and caps when no Vulkan device is '
      'registered, which the sweep E2E records as no_vulkan_device', () {
    final decided = _decide(
      VulkanDeviceProbe.devices([_facts('Mali-G715', 16)]),
      registered: 0,
    );

    expect(decided.defect, isTrue);
    expect(decided.debug, isEmpty);
    expect(
      promptCapState(
        logged: null,
        microBatchSize: 0,
        isAndroid: true,
        vulkanRequested: true,
        registeredVulkanDevices: 0,
      ),
      PromptCapState.noVulkanDevice,
    );
  });
}
