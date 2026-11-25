import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../../core/exceptions.dart';
import '../isolate_shutdown_releases.dart';
import 'bindings.dart';
import 'exit_teardown_api.dart';

typedef _Version = Uint32 Function();
typedef _Create = Pointer<Void> Function();
typedef _Activate = Bool Function(Pointer<Void>);
typedef _Release = Void Function(Pointer<Void>);
typedef _Track =
    Int32 Function(
      Pointer<Void>,
      Pointer<Void>,
      Pointer<NativeFinalizerFunction>,
      Int32,
    );
typedef _Untrack = Bool Function(Pointer<Void>, Pointer<Void>);
typedef _Load =
    Pointer<llama_model> Function(
      Pointer<Void>,
      Pointer<Char>,
      llama_model_params,
    );
typedef _Context =
    Pointer<llama_context> Function(
      Pointer<Void>,
      Pointer<llama_model>,
      llama_context_params,
    );
typedef _Mtmd =
    Pointer<mtmd_context> Function(
      Pointer<Void>,
      Pointer<Char>,
      Pointer<llama_model>,
      Pointer<mtmd_context_params>,
    );

/// Optional creation-time owner boundary. All functions must resolve from the
/// same wrapper image; an older or partial runtime retains the legacy path.
final class NativeOwnerApi {
  NativeOwnerApi._(Pointer<NativeType> Function(String) symbol)
    : create = symbol(
        'llama_dart_owner_create',
      ).cast<NativeFunction<_Create>>().asFunction(),
      activate = symbol(
        'llama_dart_owner_activate',
      ).cast<NativeFunction<_Activate>>().asFunction(),
      releaseAddress = symbol('llama_dart_owner_release').cast(),
      abandonAddress = symbol('llama_dart_owner_abandon').cast(),
      track = symbol(
        'llama_dart_owner_track',
      ).cast<NativeFunction<_Track>>().asFunction(),
      untrack = symbol(
        'llama_dart_owner_untrack',
      ).cast<NativeFunction<_Untrack>>().asFunction(),
      loadModel = symbol(
        'llama_dart_owner_model_load_from_file',
      ).cast<NativeFunction<_Load>>().asFunction(),
      createContext = symbol(
        'llama_dart_owner_init_from_model',
      ).cast<NativeFunction<_Context>>().asFunction(),
      createProjector = symbol(
        'llama_dart_owner_mtmd_init_from_file',
      ).cast<NativeFunction<_Mtmd>>().asFunction();

  /// Creates a pending token without native payload.
  final Pointer<Void> Function() create;

  /// Activates a token after stable worker cleanup is attached.
  final bool Function(Pointer<Void>) activate;

  /// Drains an owner after its worker stops.
  final Pointer<NativeFinalizerFunction> releaseAddress;

  /// Aborts pending bootstrap state without freeing active payload.
  final Pointer<NativeFinalizerFunction> abandonAddress;

  /// Registers raw state or adopts an existing process-registry identity.
  final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<NativeFinalizerFunction>,
    int,
  )
  track;

  /// Removes a raw adopted entry immediately before ordinary free.
  final bool Function(Pointer<Void>, Pointer<Void>) untrack;

  /// Creates and publishes a model inside native ownership.
  final Pointer<llama_model> Function(
    Pointer<Void>,
    Pointer<Char>,
    llama_model_params,
  )
  loadModel;

  /// Creates a context using a model belonging to the same owner.
  final Pointer<llama_context> Function(
    Pointer<Void>,
    Pointer<llama_model>,
    llama_context_params,
  )
  createContext;

  /// Creates a projector using a model belonging to the same owner.
  final Pointer<mtmd_context> Function(
    Pointer<Void>,
    Pointer<Char>,
    Pointer<llama_model>,
    Pointer<mtmd_context_params>,
  )
  createProjector;

  /// Resolves API v1 completely, returning null for absent or partial runtimes.
  static NativeOwnerApi? tryResolve({
    Pointer<NativeType> Function(String)? symbol,
  }) {
    try {
      final resolve = symbol ?? _ownerSymbol;
      final version = resolve(
        'llama_dart_owner_api_version',
      ).cast<NativeFunction<_Version>>().asFunction<int Function()>();
      if (version() != 1) return null;
      return NativeOwnerApi._(resolve);
    } on ArgumentError {
      return null;
    }
  }
}

/// Parent-held pending control token, established before spawning the worker.
/// Its finalizer never drains active payload; only worker-exit cleanup does.
final class NativeOwnerBootstrap implements Finalizable {
  NativeOwnerBootstrap._(this.api, this.token) {
    _finalizer.attach(this, token);
  }

  /// The exact wrapper boundary resolved for this token.
  final NativeOwnerApi api;

  /// Opaque native identity; never dereferenced by Dart.
  final Pointer<Void> token;
  static final Map<int, NativeFinalizer> _abandonFinalizers = {};
  NativeFinalizer get _finalizer => _abandonFinalizers.putIfAbsent(
    api.abandonAddress.address,
    () => NativeFinalizer(api.abandonAddress),
  );

  /// Establishes pending parent ownership before starting a killable worker.
  static NativeOwnerBootstrap? tryCreate() {
    final api = NativeOwnerApi.tryResolve();
    if (api == null) return null;
    final token = api.create();
    if (token == nullptr) {
      throw LlamaBackendInitializationException(
        'Could not create the native worker owner.',
      );
    }
    try {
      return NativeOwnerBootstrap._(api, token);
    } catch (_) {
      api.abandonAddress.asFunction<void Function(Pointer<Void>)>()(token);
      rethrow;
    }
  }

  /// Called only after actual onExit, or when spawn failed before a worker ran.
  /// A background isolate keeps native finalizer draining off the caller thread.
  Future<void> releaseAfterWorkerExit() async {
    await _releaseAfterExit(token.address);
  }
}

Future<void> _releaseAfterExit(int address) => Isolate.run(() {
  final api = NativeOwnerApi.tryResolve();
  if (api == null) {
    throw LlamaStateException(
      'Native owner API disappeared during worker cleanup.',
    );
  }
  api.releaseAddress.asFunction<void Function(Pointer<Void>)>()(
    Pointer.fromAddress(address),
  );
});

/// The worker installs this owner before activation or payload creation.
final class NativeWorkerOwner implements IsolateShutdownOwner {
  /// Binds an existing parent token to the worker registry.
  NativeWorkerOwner(this.api, this.token);

  /// The exact wrapper boundary resolved for this token.
  final NativeOwnerApi api;
  @override
  /// Opaque native identity; never dereferenced by Dart.
  final Pointer<Void> token;
  @override
  Pointer<NativeFinalizerFunction> get releaseAddress => api.releaseAddress;
  @override
  int track(
    ShutdownStage stage,
    Pointer<NativeFinalizerFunction> free,
    Pointer<NativeType> object,
  ) => api.track(token, object.cast(), free, exitStageValue(stage));
  @override
  void untrack(Pointer<NativeType> object) {
    if (!api.untrack(token, object.cast())) {
      throw LlamaStateException(
        'Native worker owner lost a registered object.',
      );
    }
  }
}

Pointer<NativeType> _ownerSymbol(String name) =>
    Platform.isWindows ? _wrapperSymbol(name) : _mainSymbol(name);

Pointer<NativeType> _mainSymbol(String name) => switch (name) {
  'llama_dart_owner_api_version' => Native.addressOf<NativeFunction<_Version>>(
    _mainversion,
  ),
  'llama_dart_owner_create' => Native.addressOf<NativeFunction<_Create>>(
    _maincreate,
  ),
  'llama_dart_owner_activate' => Native.addressOf<NativeFunction<_Activate>>(
    _mainactivate,
  ),
  'llama_dart_owner_release' => Native.addressOf<NativeFunction<_Release>>(
    _mainrelease,
  ),
  'llama_dart_owner_abandon' => Native.addressOf<NativeFunction<_Release>>(
    _mainabandon,
  ),
  'llama_dart_owner_track' => Native.addressOf<NativeFunction<_Track>>(
    _maintrack,
  ),
  'llama_dart_owner_untrack' => Native.addressOf<NativeFunction<_Untrack>>(
    _mainuntrack,
  ),
  'llama_dart_owner_model_load_from_file' =>
    Native.addressOf<NativeFunction<_Load>>(_mainload),
  'llama_dart_owner_init_from_model' =>
    Native.addressOf<NativeFunction<_Context>>(_maincontext),
  'llama_dart_owner_mtmd_init_from_file' =>
    Native.addressOf<NativeFunction<_Mtmd>>(_mainmtmd),
  _ => throw ArgumentError.value(name, 'name', 'Unknown owner symbol'),
};

@Native<_Version>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_api_version',
)
external int _mainversion();

@Native<_Create>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_create',
)
external Pointer<Void> _maincreate();

@Native<_Activate>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_activate',
)
external bool _mainactivate(Pointer<Void> owner);

@Native<_Release>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_release',
)
external void _mainrelease(Pointer<Void> owner);

@Native<_Release>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_abandon',
)
external void _mainabandon(Pointer<Void> owner);

@Native<_Track>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_track',
)
external int _maintrack(
  Pointer<Void> owner,
  Pointer<Void> object,
  Pointer<NativeFinalizerFunction> free,
  int stage,
);

@Native<_Untrack>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_untrack',
)
external bool _mainuntrack(Pointer<Void> owner, Pointer<Void> object);

@Native<_Load>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_model_load_from_file',
)
external Pointer<llama_model> _mainload(
  Pointer<Void> owner,
  Pointer<Char> path,
  llama_model_params params,
);

@Native<_Context>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_init_from_model',
)
external Pointer<llama_context> _maincontext(
  Pointer<Void> owner,
  Pointer<llama_model> model,
  llama_context_params params,
);

@Native<_Mtmd>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llama_dart_owner_mtmd_init_from_file',
)
external Pointer<mtmd_context> _mainmtmd(
  Pointer<Void> owner,
  Pointer<Char> path,
  Pointer<llama_model> model,
  Pointer<mtmd_context_params> params,
);

Pointer<NativeType> _wrapperSymbol(String name) => switch (name) {
  'llama_dart_owner_api_version' => Native.addressOf<NativeFunction<_Version>>(
    _wrapperversion,
  ),
  'llama_dart_owner_create' => Native.addressOf<NativeFunction<_Create>>(
    _wrappercreate,
  ),
  'llama_dart_owner_activate' => Native.addressOf<NativeFunction<_Activate>>(
    _wrapperactivate,
  ),
  'llama_dart_owner_release' => Native.addressOf<NativeFunction<_Release>>(
    _wrapperrelease,
  ),
  'llama_dart_owner_abandon' => Native.addressOf<NativeFunction<_Release>>(
    _wrapperabandon,
  ),
  'llama_dart_owner_track' => Native.addressOf<NativeFunction<_Track>>(
    _wrappertrack,
  ),
  'llama_dart_owner_untrack' => Native.addressOf<NativeFunction<_Untrack>>(
    _wrapperuntrack,
  ),
  'llama_dart_owner_model_load_from_file' =>
    Native.addressOf<NativeFunction<_Load>>(_wrapperload),
  'llama_dart_owner_init_from_model' =>
    Native.addressOf<NativeFunction<_Context>>(_wrappercontext),
  'llama_dart_owner_mtmd_init_from_file' =>
    Native.addressOf<NativeFunction<_Mtmd>>(_wrappermtmd),
  _ => throw ArgumentError.value(name, 'name', 'Unknown owner symbol'),
};

@Native<_Version>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_api_version',
)
external int _wrapperversion();

@Native<_Create>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_create',
)
external Pointer<Void> _wrappercreate();

@Native<_Activate>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_activate',
)
external bool _wrapperactivate(Pointer<Void> owner);

@Native<_Release>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_release',
)
external void _wrapperrelease(Pointer<Void> owner);

@Native<_Release>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_abandon',
)
external void _wrapperabandon(Pointer<Void> owner);

@Native<_Track>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_track',
)
external int _wrappertrack(
  Pointer<Void> owner,
  Pointer<Void> object,
  Pointer<NativeFinalizerFunction> free,
  int stage,
);

@Native<_Untrack>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_untrack',
)
external bool _wrapperuntrack(Pointer<Void> owner, Pointer<Void> object);

@Native<_Load>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_model_load_from_file',
)
external Pointer<llama_model> _wrapperload(
  Pointer<Void> owner,
  Pointer<Char> path,
  llama_model_params params,
);

@Native<_Context>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_init_from_model',
)
external Pointer<llama_context> _wrappercontext(
  Pointer<Void> owner,
  Pointer<llama_model> model,
  llama_context_params params,
);

@Native<_Mtmd>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_owner_mtmd_init_from_file',
)
external Pointer<mtmd_context> _wrappermtmd(
  Pointer<Void> owner,
  Pointer<Char> path,
  Pointer<llama_model> model,
  Pointer<mtmd_context_params> params,
);
