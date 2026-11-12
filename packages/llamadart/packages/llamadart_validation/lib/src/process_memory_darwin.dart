import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Names the macOS and iOS footprint counter.
const darwinFootprintSource = 'task_info(TASK_VM_INFO).phys_footprint';

/// `TASK_VM_INFO` in `<mach/task_info.h>`.
const taskVmInfoFlavor = 22;

/// `TASK_VM_INFO_REV1_COUNT`: the `natural_t` words up to and including
/// `phys_footprint`.
const taskVmInfoRev1Count = 38;

/// `task_vm_info_data_t` up to and including `phys_footprint`, which the
/// kernel fills when given [taskVmInfoRev1Count] words.
@Packed(4)
final class TaskVmInfoRev1 extends Struct {
  @Uint64()
  external int virtualSize;
  @Int32()
  external int regionCount;
  @Int32()
  external int pageSize;
  @Uint64()
  external int residentSize;
  @Uint64()
  external int residentSizePeak;
  @Uint64()
  external int device;
  @Uint64()
  external int devicePeak;
  @Uint64()
  external int internal;
  @Uint64()
  external int internalPeak;
  @Uint64()
  external int external;
  @Uint64()
  external int externalPeak;
  @Uint64()
  external int reusable;
  @Uint64()
  external int reusablePeak;
  @Uint64()
  external int purgeableVolatilePmap;
  @Uint64()
  external int purgeableVolatileResident;
  @Uint64()
  external int purgeableVolatileVirtual;
  @Uint64()
  external int compressed;
  @Uint64()
  external int compressedPeak;
  @Uint64()
  external int compressedLifetime;
  @Uint64()
  external int physFootprint;
}

/// `phys_footprint` from a `task_info` call that returned [kernReturn] and
/// filled [count] words of [info], or null unless the call succeeded and
/// filled `phys_footprint`.
int? darwinFootprintFrom(int kernReturn, int count, TaskVmInfoRev1 info) =>
    kernReturn == 0 && count >= taskVmInfoRev1Count ? info.physFootprint : null;

/// Calls `task_info(TASK_VM_INFO)` for this task and passes the result to
/// [read].
R? readTaskVmInfo<R>(
  R? Function(int kernReturn, int count, TaskVmInfoRev1 info) read,
) {
  final process = DynamicLibrary.process();
  final task = process.lookup<Uint32>('mach_task_self_').value;
  final taskInfo = process
      .lookupFunction<
        Int32 Function(Uint32, Int32, Pointer<TaskVmInfoRev1>, Pointer<Uint32>),
        int Function(int, int, Pointer<TaskVmInfoRev1>, Pointer<Uint32>)
      >('task_info');
  final info = calloc<TaskVmInfoRev1>();
  final count = calloc<Uint32>()..value = taskVmInfoRev1Count;
  try {
    final result = taskInfo(task, taskVmInfoFlavor, info, count);
    return read(result, count.value, info.ref);
  } finally {
    calloc.free(info);
    calloc.free(count);
  }
}

/// This task's `phys_footprint` in bytes, or null when `task_info` fails.
int? readDarwinFootprint() => readTaskVmInfo(darwinFootprintFrom);
