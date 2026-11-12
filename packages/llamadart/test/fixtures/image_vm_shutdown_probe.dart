// Model-backed local fixture: pending image work is disposed before natural
// Dart VM termination. Native callbacks remain entirely in the C observer.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart' as native;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;

Future<void> main(List<String> args) async {
  final [work, model, observerPath] = args;
  final observer = DynamicLibrary.open(observerPath);
  final initialize = observer
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Void>),
        int Function(Pointer<Utf8>, Pointer<Void>)
      >('flutter_shutdown_observer_init');
  final initialized = using(
    (arena) => initialize(
      observerPath.toNativeUtf8(allocator: arena),
      Native.addressOf<NativeFunction<Int32 Function()>>(
        native.llama_dart_exit_tracked_count,
      ).cast(),
    ),
  );
  if (initialized != 0) {
    throw StateError('Host observer did not initialize.');
  }
  observer.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('flutter_shutdown_image_init')(
    Native.addressOf<NativeFunction<Int32 Function()>>(
      sd.sd_dart_exit_tracked_count,
    ).cast(),
  );
  var loadReturned = false;
  final loading = ImageGenerationEngine.load(
    ImageGenerationModel(ModelSource.path(model)),
    params: ImageModelParams(
      device: Platform.isMacOS ? ComputeDevice.gpu : ComputeDevice.cpu,
      threads: 4,
    ),
  );
  unawaited(
    loading.then((_) {
      loadReturned = true;
    }),
  );
  ImageGenerationTask? task;
  StreamSubscription<ImageGenerationEvent>? subscription;
  if (work == 'image-loading') {
    final reports = calloc<sd.sd_dart_progress_t>(1);
    final latest = calloc<Uint64>();
    try {
      while (sd.sd_dart_progress_read(0, reports, 1, latest) == 0) {
        if (loadReturned) {
          throw StateError('Load finished before shutdown request.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      if (loadReturned) {
        throw StateError('Load finished before shutdown request.');
      }
      stdout.writeln('IMAGE_VM_SHUTDOWN_REQUEST loading');
    } finally {
      calloc.free(reports);
      calloc.free(latest);
    }
  }
  final engine = await loading;
  stdout.writeln('IMAGE_VM_BACKEND ${(await engine.capabilities).backendName}');
  if (work == 'image-generating') {
    task = await engine.generate(
      const ImageGenerationRequest(
        prompt: 'a red fox in autumn leaves',
        width: 256,
        height: 256,
        steps: 40,
        guidanceScale: 1,
        seed: 42,
      ),
    );
    var completed = false;
    unawaited(
      task.done.then((_) {
        completed = true;
      }),
    );
    final first = Completer<void>();
    subscription = task.events.listen((event) {
      if (event is ImageGenerationProgressEvent &&
          event.phase == ImageGenerationPhase.sampling &&
          event.step > 0 &&
          event.step < event.steps &&
          !first.isCompleted) {
        first.complete();
      }
    });
    await first.future;
    if (completed) {
      throw StateError('Generation finished before shutdown request.');
    }
    stdout.writeln('IMAGE_VM_SHUTDOWN_REQUEST generating');
  } else if (work != 'image-loading') {
    throw ArgumentError.value(work, 'work');
  }
  final disposal = engine.dispose();
  await engine.dispose();
  await disposal;
  if (task != null) {
    final completion = await task.done;
    if (completion.state == ImageGenerationCompletionState.failed) {
      throw completion.error!;
    }
    stdout.writeln('IMAGE_VM_COMPLETION ${completion.state.name}');
  }
  await subscription?.cancel();
  if (sd.sd_dart_exit_tracked_count() != 0) {
    throw StateError('Image objects remain after disposal.');
  }
  stdout.writeln('IMAGE_VM_RETURN disposed');
  // Return naturally. No dart:io exit or direct C exit is called.
}
