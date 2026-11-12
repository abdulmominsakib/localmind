import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../core/image/image_generation_driver.dart';
import '../../core/models/config/log_level.dart';
import 'stable_diffusion_bindings.dart' as sd;
import 'stable_diffusion_calls.dart';
import 'stable_diffusion_log.dart';

export '../../core/image/image_generation_driver.dart'
    show StableDiffusionGpuMemory;

/// Up to [length] bytes of the file at [path] from [offset]; fewer at its end.
Future<Uint8List> readStableDiffusionFileRange(
  String path,
  int offset,
  int length,
) async {
  final file = await File(path).open();
  try {
    await file.setPosition(offset);
    return await file.read(length);
  } finally {
    await file.close();
  }
}

/// Size of the regular file at [path] in bytes, or `null` when there is none.
int? stableDiffusionFileSize(String path) {
  final file = File(path);
  try {
    return file.statSync().type == FileSystemEntityType.file
        ? file.lengthSync()
        : null;
  } on FileSystemException {
    return null;
  }
}

/// Memory a new image model can use on [device], and where the figure came
/// from, or `null` when it is not known.
///
/// On the CPU, host memory:
/// - Android: the larger of `MemAvailable` from `/proc/meminfo` and half of
///   `MemTotal` less the app's own memory (`VmRSS` plus `VmSwap`).
///   `MemAvailable`
///   leaves out what the low-memory killer frees by stopping cached apps and
///   what it swaps to zram: on six 4 to 16 GB phones, a foreground app that
///   kept touching all of its memory was killed only after allocating 0.9 to
///   3.6 GiB more than `MemAvailable`, 53 to 84% of `MemTotal`.
/// - Linux: `MemAvailable`, the memory the kernel can hand out without
///   swapping.
/// - iOS: `os_proc_available_memory()`, what the app can still allocate
///   before it reaches its memory limit.
/// - macOS: physical memory (`hw.memsize`). macOS compresses and swaps, so
///   only a model that cannot fit at all is refused.
/// - Windows and others: `null`; the check is skipped.
///
/// On Metal, the same figure, capped on macOS by the GPU's
/// `recommendedMaxWorkingSetSize`: about two thirds to three quarters of
/// physical memory, beyond which Metal buffers page.
///
/// On other GPUs, such as Vulkan, `null`: the weights live in device memory,
/// so host memory would be the wrong figure. [readStableDiffusionGpuMemory]
/// and [stableDiffusionGpuMemoryLimits] give theirs.
///
/// [abi], [readMemInfo], [readProcessStatus], [iosAvailableMemory],
/// [macosPhysicalMemory] and [metalRecommendedWorkingSet] default to the
/// host; tests replace them.
({int bytes, String source})? readStableDiffusionMemoryBudget({
  ImageGenerationComputeDevice device = ImageGenerationComputeDevice.cpu,
  Abi? abi,
  String? Function() readMemInfo = _readProcMemInfo,
  String? Function() readProcessStatus = _readProcSelfStatus,
  int? Function() iosAvailableMemory = _iosAvailableMemory,
  int? Function() macosPhysicalMemory = _macosPhysicalMemory,
  int? Function() metalRecommendedWorkingSet = _metalRecommendedWorkingSet,
}) {
  if (device == ImageGenerationComputeDevice.otherGpu) {
    return null;
  }
  final target = abi ?? Abi.current();
  final os = target.toString().split('_').first;
  final (int?, String) reading = switch (os) {
    'android' => _androidMemoryBudget(readMemInfo(), readProcessStatus()),
    'linux' => (
      switch (readMemInfo()) {
        final String memInfo => parseProcMemoryBytes(memInfo, 'MemAvailable'),
        null => null,
      },
      _memAvailableSource,
    ),
    'ios' => (iosAvailableMemory(), "the app's remaining iOS memory limit"),
    'macos' => (macosPhysicalMemory(), 'physical memory'),
    _ => (null, ''),
  };
  final bytes = reading.$1;
  if (bytes == null || bytes <= 0) {
    return null;
  }
  if (os == 'macos' && device == ImageGenerationComputeDevice.metal) {
    final workingSet = metalRecommendedWorkingSet();
    if (workingSet != null && workingSet > 0 && workingSet < bytes) {
      return (bytes: workingSet, source: "Metal's recommended GPU working set");
    }
  }
  return (bytes: bytes, source: reading.$2);
}

/// The memory of every GPU the runtime lists, discrete and integrated, in
/// the runtime's device order, from `sd_dart_gpu_device_count` and
/// `sd_dart_gpu_device_memory`, or `null` when it is not known:
///
/// - the runtime is older than `StableDiffusionCalls.optionalNativeRelease`
///   and does not export the queries;
/// - the runtime has no GPU backend or found no GPU, or one of the devices
///   does not report its memory;
/// - `SD_VK_DEVICE` is set, which can make the runtime pick a Vulkan device
///   by number.
///
/// The first query in a process initializes the GPU backend, as a load
/// otherwise does, which can take many seconds, and exit teardown waits for
/// a query in flight: call it from an isolate that may block, never from a UI
/// isolate. The runtime's recorder is registered first at [logLevel], because
/// a query logs through ggml and the registration is not synchronized with
/// it.
///
/// [resolveCalls] and [environment] default to the bundled runtime and the
/// process environment; tests replace them.
List<StableDiffusionGpuMemory>? readStableDiffusionGpuMemory({
  StableDiffusionCalls? Function() resolveCalls =
      StableDiffusionCalls.tryResolve,
  LlamaLogLevel logLevel = LlamaLogLevel.none,
  String? Function(String name) environment = _environmentVariable,
}) {
  if (environment('SD_VK_DEVICE') != null) {
    return null;
  }
  final calls = resolveCalls();
  final gpu = calls?.gpu;
  if (calls == null || gpu == null) {
    return null;
  }
  final log = calls.log;
  if (log != null) {
    recordStableDiffusionLog(log, logLevel);
  }
  final count = gpu.deviceCount();
  if (count <= 0) {
    return null;
  }
  return using((arena) {
    final out = arena<sd.sd_dart_gpu_device_memory_t>();
    final devices = <StableDiffusionGpuMemory>[];
    for (var index = 0; index < count; index++) {
      final status = gpu.deviceMemory(index, out);
      if (status != sd.sd_dart_gpu_status.SD_DART_GPU_OK.value) {
        return null;
      }
      final memory = out.ref;
      final name = _text(memory.name, 64);
      final description = _text(memory.description, 256);
      devices.add((
        name: description.isEmpty ? name : '$name ($description)',
        totalBytes: memory.total_bytes,
        freeBytes: memory.free_bytes,
        integrated:
            memory.type ==
            sd.sd_dart_gpu_device_type.SD_DART_GPU_DEVICE_INTEGRATED.value,
      ));
    }
    return devices;
  });
}

/// The memory limits of a new image model on the GPUs [gpus] describes, in
/// the runtime's device order; neither is known when [gpus] is `null` or
/// empty, or one of them reports no memory.
///
/// A GPU's figure:
/// - with a budget from the driver (`VK_EXT_memory_budget`), its free memory,
///   which is what this process can still allocate there and so accounts for
///   other processes and for models already loaded;
/// - without one, its total memory. The runtime then reports the total as
///   free, so equal figures mean "not reported". A free figure of 0 is a
///   budget below the process's use, and counts as no free memory.
///
/// Discrete GPUs do not bound a load by themselves: stable-diffusion.cpp's
/// automatic fit, which llamadart leaves on, keeps the weights that do not
/// fit the GPU it computes on in host memory, or on another GPU. That GPU is
/// the discrete one with the most free memory when [runtimePicksGpu] (no
/// backend is named), and the first discrete one for the backend `gpu`. So a
/// model above that GPU's figure is only `slower`, and it is refused above
/// the figures of all discrete GPUs plus [hostBudget], the figure the CPU
/// gets. Where host memory is not read, as on Windows, nothing is refused.
///
/// An integrated GPU uses host memory, and a driver that exposes that as
/// several heaps has it counted more than once in the device's figures. They
/// are never used: beside a discrete GPU an integrated one adds nothing, and
/// with integrated GPUs only a model is refused above [hostBudget] alone.
ImageGenerationMemoryLimits stableDiffusionGpuMemoryLimits(
  List<StableDiffusionGpuMemory>? gpus, {
  required bool runtimePicksGpu,
  required ImageGenerationMemoryBudget? Function() hostBudget,
}) {
  if (gpus == null || gpus.isEmpty || gpus.any((gpu) => gpu.totalBytes <= 0)) {
    return (refuse: null, slower: null);
  }
  final host = hostBudget();
  final discrete = [
    for (final gpu in gpus)
      if (!gpu.integrated) _gpuFigure(gpu),
  ];
  if (discrete.isEmpty) {
    return (
      refuse: host == null
          ? null
          : (
              bytes: host.bytes,
              source:
                  '${host.source}; ${gpus.first.name} is an integrated GPU, '
                  'which uses host memory',
            ),
      slower: null,
    );
  }
  var computing = discrete.first;
  if (runtimePicksGpu) {
    for (final figure in discrete.skip(1)) {
      if (figure.bytes > computing.bytes) {
        computing = figure;
      }
    }
  }
  final gpuBytes = discrete.fold(0, (sum, figure) => sum + figure.bytes);
  return (
    refuse: host == null
        ? null
        : (
            bytes: gpuBytes + host.bytes,
            source: [
              if (discrete.length == 1)
                '${_gib(gpuBytes)} GiB of GPU memory and '
                    '${_gib(host.bytes)} GiB of system memory: '
                    '${discrete.single.source}'
              else ...[
                '${_gib(gpuBytes)} GiB of GPU memory on ${discrete.length} '
                    'GPUs and ${_gib(host.bytes)} GiB of system memory: '
                    '${_gib(discrete.first.bytes)} GiB, '
                    '${discrete.first.source}',
                for (final figure in discrete.skip(1))
                  '${_gib(figure.bytes)} GiB, ${figure.source}',
              ],
              host.source,
            ].join('; '),
          ),
    slower: computing,
  );
}

ImageGenerationMemoryBudget _gpuFigure(StableDiffusionGpuMemory gpu) =>
    gpu.freeBytes < gpu.totalBytes
    ? (
        bytes: gpu.freeBytes,
        source:
            'free GPU memory of ${gpu.name}, out of '
            '${_gib(gpu.totalBytes)} GiB',
      )
    : (
        bytes: gpu.totalBytes,
        source:
            'the GPU memory of ${gpu.name}, whose driver does not report how '
            'much of it is free',
      );

String _gib(int bytes) {
  final gib = bytes / (1 << 30);
  return gib.toStringAsFixed(gib < 10 ? 2 : 1);
}

String _text(Array<Char> characters, int length) {
  final bytes = <int>[];
  for (var i = 0; i < length; i++) {
    final byte = characters[i] & 0xff;
    if (byte == 0) {
      break;
    }
    bytes.add(byte);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _environmentVariable(String name) => Platform.environment[name];

const String _memAvailableSource = 'MemAvailable in /proc/meminfo';

(int?, String) _androidMemoryBudget(String? memInfo, String? status) {
  if (memInfo == null) {
    return (null, _memAvailableSource);
  }
  final available = parseProcMemoryBytes(memInfo, 'MemAvailable');
  final total = parseProcMemoryBytes(memInfo, 'MemTotal');
  final resident = status == null
      ? null
      : parseProcMemoryBytes(status, 'VmRSS');
  if (total == null || resident == null) {
    return (available, _memAvailableSource);
  }
  final swapped = parseProcMemoryBytes(status!, 'VmSwap') ?? 0;
  final halfLessApp = total ~/ 2 - resident - swapped;
  if (available != null && available >= halfLessApp) {
    return (available, _memAvailableSource);
  }
  return (
    halfLessApp,
    "half of MemTotal in /proc/meminfo less the app's memory",
  );
}

/// The `[field]:  <n> kB` line of `/proc/meminfo` or `/proc/self/status`
/// text, in bytes, or `null` when it is missing or malformed (kernels before
/// 3.14 do not report `MemAvailable`).
int? parseProcMemoryBytes(String text, String field) {
  final match = RegExp(
    '^${RegExp.escape(field)}:\\s+(\\d+)\\s*kB\\s*\$',
    multiLine: true,
  ).firstMatch(text);
  final kib = match == null ? null : int.tryParse(match.group(1)!);
  return kib == null ? null : kib * 1024;
}

String? _readProcMemInfo() => _readProcFile('/proc/meminfo');

String? _readProcSelfStatus() => _readProcFile('/proc/self/status');

String? _readProcFile(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

int? _iosAvailableMemory() {
  try {
    final available = DynamicLibrary.process()
        .lookupFunction<Size Function(), int Function()>(
          'os_proc_available_memory',
        );
    return available();
  } on ArgumentError {
    return null;
  }
}

int? _macosPhysicalMemory() {
  try {
    final sysctlbyname = DynamicLibrary.process()
        .lookupFunction<
          Int Function(
            Pointer<Utf8>,
            Pointer<Void>,
            Pointer<Size>,
            Pointer<Void>,
            Size,
          ),
          int Function(
            Pointer<Utf8>,
            Pointer<Void>,
            Pointer<Size>,
            Pointer<Void>,
            int,
          )
        >('sysctlbyname');
    return using((arena) {
      final value = arena<Uint64>();
      final length = arena<Size>()..value = sizeOf<Uint64>();
      final status = sysctlbyname(
        'hw.memsize'.toNativeUtf8(allocator: arena),
        value.cast(),
        length,
        nullptr,
        0,
      );
      return status == 0 ? value.value : null;
    });
  } on ArgumentError {
    return null;
  }
}

/// `MTLCreateSystemDefaultDevice().recommendedMaxWorkingSetSize`, through the
/// Objective-C runtime, or `null` without a Metal device.
int? _metalRecommendedWorkingSet() {
  try {
    final metal = DynamicLibrary.open(
      '/System/Library/Frameworks/Metal.framework/Metal',
    );
    final objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
    final createDevice = metal
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'MTLCreateSystemDefaultDevice',
        );
    final selector = objc
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('sel_registerName');
    final sendUint64 = objc
        .lookupFunction<
          Uint64 Function(Pointer<Void>, Pointer<Void>),
          int Function(Pointer<Void>, Pointer<Void>)
        >('objc_msgSend');
    final sendVoid = objc
        .lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
        >('objc_msgSend');
    return using((arena) {
      Pointer<Void> select(String name) =>
          selector(name.toNativeUtf8(allocator: arena));
      final device = createDevice();
      if (device == nullptr) {
        return null;
      }
      try {
        return sendUint64(device, select('recommendedMaxWorkingSetSize'));
      } finally {
        sendVoid(device, select('release'));
      }
    });
  } on ArgumentError {
    return null;
  }
}
