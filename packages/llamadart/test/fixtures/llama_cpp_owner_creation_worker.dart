import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart' as native;
import 'package:llamadart/src/backends/llama_cpp/native_owner_api.dart';

typedef _Load =
    Pointer<native.llama_model> Function(
      Pointer<Void>,
      Pointer<Char>,
      native.llama_model_params,
    );
typedef _Context =
    Pointer<native.llama_context> Function(
      Pointer<Void>,
      Pointer<native.llama_model>,
      native.llama_context_params,
    );
typedef _GatedLoad =
    Pointer<native.llama_model> Function(
      Pointer<NativeFunction<_Load>>,
      Pointer<Void>,
      Pointer<Char>,
      native.llama_model_params,
    );
typedef _GatedContext =
    Pointer<native.llama_context> Function(
      Pointer<NativeFunction<_Context>>,
      Pointer<Void>,
      Pointer<native.llama_model>,
      native.llama_context_params,
    );

void main(List<String> arguments, SendPort parent) {
  runOwnerCreationWorker([
    ...arguments.take(4),
    int.parse(arguments[4]),
    parent,
  ]);
}

void runOwnerCreationWorker(List<Object?> arguments) {
  final [libraryPath, gatePath, modelPath, phase, address, reports] = arguments;
  final library = DynamicLibrary.open(libraryPath! as String);
  final gate = DynamicLibrary.open(gatePath! as String);
  final api = NativeOwnerApi.tryResolve(symbol: library.lookup)!;
  final token = Pointer<Void>.fromAddress(address! as int);
  IsolateShutdownReleases.current.installOwner(NativeWorkerOwner(api, token));
  if (!api.activate(token)) throw StateError('Bootstrap expired');
  library.lookupFunction<Void Function(), void Function()>(
    'llama_backend_init',
  )();
  final params = library
      .lookupFunction<
        native.llama_model_params Function(),
        native.llama_model_params Function()
      >('llama_model_default_params')();
  params.n_gpu_layers = 0;
  final path = (modelPath! as String).toNativeUtf8();
  Pointer<native.llama_model> model;
  if (phase == 'model') {
    final create = library.lookup<NativeFunction<_Load>>(
      'llama_dart_owner_model_load_from_file',
    );
    model = gate
        .lookupFunction<
          _GatedLoad,
          Pointer<native.llama_model> Function(
            Pointer<NativeFunction<_Load>>,
            Pointer<Void>,
            Pointer<Char>,
            native.llama_model_params,
          )
        >('owner_gate_model')(create, token, path.cast(), params);
  } else {
    model = api.loadModel(token, path.cast(), params);
    final contextParams =
        library.lookupFunction<
            native.llama_context_params Function(),
            native.llama_context_params Function()
          >('llama_context_default_params')()
          ..n_ctx = 256
          ..n_batch = 32
          ..n_ubatch = 32
          ..n_threads = 2
          ..n_threads_batch = 2;
    final create = library.lookup<NativeFunction<_Context>>(
      'llama_dart_owner_init_from_model',
    );
    gate.lookupFunction<
      _GatedContext,
      Pointer<native.llama_context> Function(
        Pointer<NativeFunction<_Context>>,
        Pointer<Void>,
        Pointer<native.llama_model>,
        native.llama_context_params,
      )
    >('owner_gate_context')(create, token, model, contextParams);
  }
  (reports! as SendPort).send('Unexpected Dart result handling');
}
