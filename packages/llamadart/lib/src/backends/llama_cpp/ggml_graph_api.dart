import 'dart:ffi';
import 'dart:io';

import '../../core/exceptions.dart';
import 'bindings.dart';

/// Runs [body], turning a failure to resolve a native function into a
/// [LlamaUnsupportedException]; other errors pass through.
T withGgmlGraphSymbols<T>(T Function() body) {
  try {
    return body();
  } on ArgumentError catch (error) {
    final message = '${error.message}';
    if (!message.contains("Couldn't resolve native function")) rethrow;
    throw LlamaUnsupportedException(
      'The loaded native library does not export a ggml function the decision '
      'head calls; use a llamadart native bundle that exports it. ($message)',
    );
  }
}

/// The ggml graph, scheduler and buffer functions the decision head calls.
///
/// Enum arguments and results are their integer values. Windows bundles export
/// these functions from `ggml-base.dll` and `ggml.dll` rather than the default
/// `llama.dll` asset, so [current] binds `@Native` declarations to those assets
/// on Windows. Elsewhere it uses the generated bindings, plus one `@Native` on
/// their default asset for `ggml_backend_alloc_ctx_tensors`, which the bindings
/// leave out with the rest of `ggml-alloc.h`.
final class GgmlGraphApi {
  const GgmlGraphApi._({
    required this.init,
    required this.free,
    required this.tensorOverhead,
    required this.graphOverheadCustom,
    required this.newTensor1d,
    required this.newTensor2d,
    required this.setInput,
    required this.setOutput,
    required this.add,
    required this.mul,
    required this.mulMat,
    required this.getRows,
    required this.norm,
    required this.reshape3d,
    required this.permute,
    required this.softMaxExt,
    required this.cont,
    required this.cont2d,
    required this.transpose,
    required this.relu,
    required this.geluErf,
    required this.newGraphCustom,
    required this.buildForwardExpand,
    required this.devByType,
    required this.devInit,
    required this.backendName,
    required this.backendGetDevice,
    required this.devBackendReg,
    required this.regGetProcAddress,
    required this.backendFree,
    required this.allocCtxTensors,
    required this.bufferSetUsage,
    required this.bufferFree,
    required this.tensorSet,
    required this.tensorGet,
    required this.schedNew,
    required this.schedReset,
    required this.schedAllocGraph,
    required this.schedGraphCompute,
    required this.schedSynchronize,
    required this.schedFree,
  });

  /// The functions for the running platform.
  static final GgmlGraphApi current = Platform.isWindows
      ? _windowsApi
      : _bindingsApi;

  /// `ggml_init`.
  final Pointer<ggml_context> Function(ggml_init_params params) init;

  /// `ggml_free`.
  final void Function(Pointer<ggml_context> ctx) free;

  /// `ggml_tensor_overhead`.
  final int Function() tensorOverhead;

  /// `ggml_graph_overhead_custom`.
  final int Function(int size, bool grads) graphOverheadCustom;

  /// `ggml_new_tensor_1d`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    int type,
    int ne0,
  )
  newTensor1d;

  /// `ggml_new_tensor_2d`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    int type,
    int ne0,
    int ne1,
  )
  newTensor2d;

  /// `ggml_set_input`.
  final void Function(Pointer<ggml_tensor> tensor) setInput;

  /// `ggml_set_output`.
  final void Function(Pointer<ggml_tensor> tensor) setOutput;

  /// `ggml_add`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    Pointer<ggml_tensor> b,
  )
  add;

  /// `ggml_mul`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    Pointer<ggml_tensor> b,
  )
  mul;

  /// `ggml_mul_mat`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    Pointer<ggml_tensor> b,
  )
  mulMat;

  /// `ggml_get_rows`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    Pointer<ggml_tensor> b,
  )
  getRows;

  /// `ggml_norm`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    double eps,
  )
  norm;

  /// `ggml_reshape_3d`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    int ne0,
    int ne1,
    int ne2,
  )
  reshape3d;

  /// `ggml_permute`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    int axis0,
    int axis1,
    int axis2,
    int axis3,
  )
  permute;

  /// `ggml_soft_max_ext`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    Pointer<ggml_tensor> mask,
    double scale,
    double maxBias,
  )
  softMaxExt;

  /// `ggml_cont`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
  )
  cont;

  /// `ggml_cont_2d`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
    int ne0,
    int ne1,
  )
  cont2d;

  /// `ggml_transpose`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
  )
  transpose;

  /// `ggml_relu`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
  )
  relu;

  /// `ggml_gelu_erf`.
  final Pointer<ggml_tensor> Function(
    Pointer<ggml_context> ctx,
    Pointer<ggml_tensor> a,
  )
  geluErf;

  /// `ggml_new_graph_custom`.
  final Pointer<ggml_cgraph> Function(
    Pointer<ggml_context> ctx,
    int size,
    bool grads,
  )
  newGraphCustom;

  /// `ggml_build_forward_expand`.
  final void Function(Pointer<ggml_cgraph> graph, Pointer<ggml_tensor> tensor)
  buildForwardExpand;

  /// `ggml_backend_dev_by_type`.
  final ggml_backend_dev_t Function(int type) devByType;

  /// `ggml_backend_dev_init`.
  final ggml_backend_t Function(ggml_backend_dev_t device, Pointer<Char> params)
  devInit;

  /// `ggml_backend_name`.
  final Pointer<Char> Function(ggml_backend_t backend) backendName;

  /// `ggml_backend_get_device`.
  final ggml_backend_dev_t Function(ggml_backend_t backend) backendGetDevice;

  /// `ggml_backend_dev_backend_reg`.
  final ggml_backend_reg_t Function(ggml_backend_dev_t device) devBackendReg;

  /// `ggml_backend_reg_get_proc_address`.
  final Pointer<Void> Function(ggml_backend_reg_t reg, Pointer<Char> name)
  regGetProcAddress;

  /// `ggml_backend_free`.
  final void Function(ggml_backend_t backend) backendFree;

  /// `ggml_backend_alloc_ctx_tensors`.
  final ggml_backend_buffer_t Function(
    Pointer<ggml_context> ctx,
    ggml_backend_t backend,
  )
  allocCtxTensors;

  /// `ggml_backend_buffer_set_usage`.
  final void Function(ggml_backend_buffer_t buffer, int usage) bufferSetUsage;

  /// `ggml_backend_buffer_free`.
  final void Function(ggml_backend_buffer_t buffer) bufferFree;

  /// `ggml_backend_tensor_set`.
  final void Function(
    Pointer<ggml_tensor> tensor,
    Pointer<Void> data,
    int offset,
    int size,
  )
  tensorSet;

  /// `ggml_backend_tensor_get`.
  final void Function(
    Pointer<ggml_tensor> tensor,
    Pointer<Void> data,
    int offset,
    int size,
  )
  tensorGet;

  /// `ggml_backend_sched_new`.
  final ggml_backend_sched_t Function(
    Pointer<ggml_backend_t> backends,
    Pointer<ggml_backend_buffer_type_t> bufts,
    int count,
    int graphSize,
    bool parallel,
    bool opOffload,
  )
  schedNew;

  /// `ggml_backend_sched_reset`.
  final void Function(ggml_backend_sched_t sched) schedReset;

  /// `ggml_backend_sched_alloc_graph`.
  final bool Function(ggml_backend_sched_t sched, Pointer<ggml_cgraph> graph)
  schedAllocGraph;

  /// `ggml_backend_sched_graph_compute`.
  final int Function(ggml_backend_sched_t sched, Pointer<ggml_cgraph> graph)
  schedGraphCompute;

  /// `ggml_backend_sched_synchronize`.
  final void Function(ggml_backend_sched_t sched) schedSynchronize;

  /// `ggml_backend_sched_free`.
  final void Function(ggml_backend_sched_t sched) schedFree;
}

/// The ggml functions that free a scheduler, a buffer and a backend, for
/// `IsolateShutdownReleases`; from the same assets as [GgmlGraphApi.current].
final ({
  Pointer<NativeFinalizerFunction> schedFree,
  Pointer<NativeFinalizerFunction> bufferFree,
  Pointer<NativeFinalizerFunction> backendFree,
})
ggmlFreeAddresses = Platform.isWindows
    ? (
        schedFree:
            Native.addressOf<
                  NativeFunction<Void Function(ggml_backend_sched_t)>
                >(_windowsSchedFree)
                .cast(),
        bufferFree:
            Native.addressOf<
                  NativeFunction<Void Function(ggml_backend_buffer_t)>
                >(_windowsBufferFree)
                .cast(),
        backendFree:
            Native.addressOf<NativeFunction<Void Function(ggml_backend_t)>>(
              _windowsBackendFree,
            ).cast(),
      )
    : (
        schedFree:
            Native.addressOf<
                  NativeFunction<Void Function(ggml_backend_sched_t)>
                >(ggml_backend_sched_free)
                .cast(),
        bufferFree:
            Native.addressOf<
                  NativeFunction<Void Function(ggml_backend_buffer_t)>
                >(ggml_backend_buffer_free)
                .cast(),
        backendFree:
            Native.addressOf<NativeFunction<Void Function(ggml_backend_t)>>(
              ggml_backend_free,
            ).cast(),
      );

final GgmlGraphApi _bindingsApi = GgmlGraphApi._(
  init: ggml_init,
  free: ggml_free,
  tensorOverhead: ggml_tensor_overhead,
  graphOverheadCustom: ggml_graph_overhead_custom,
  newTensor1d: (ctx, type, ne0) =>
      ggml_new_tensor_1d(ctx, ggml_type.fromValue(type), ne0),
  newTensor2d: (ctx, type, ne0, ne1) =>
      ggml_new_tensor_2d(ctx, ggml_type.fromValue(type), ne0, ne1),
  setInput: ggml_set_input,
  setOutput: ggml_set_output,
  add: ggml_add,
  mul: ggml_mul,
  mulMat: ggml_mul_mat,
  getRows: ggml_get_rows,
  norm: ggml_norm,
  reshape3d: ggml_reshape_3d,
  permute: ggml_permute,
  softMaxExt: ggml_soft_max_ext,
  cont: ggml_cont,
  cont2d: ggml_cont_2d,
  transpose: ggml_transpose,
  relu: ggml_relu,
  geluErf: ggml_gelu_erf,
  newGraphCustom: ggml_new_graph_custom,
  buildForwardExpand: ggml_build_forward_expand,
  devByType: (type) =>
      ggml_backend_dev_by_type(ggml_backend_dev_type.fromValue(type)),
  devInit: ggml_backend_dev_init,
  backendName: ggml_backend_name,
  backendGetDevice: ggml_backend_get_device,
  devBackendReg: ggml_backend_dev_backend_reg,
  regGetProcAddress: ggml_backend_reg_get_proc_address,
  backendFree: ggml_backend_free,
  allocCtxTensors: _allocCtxTensors,
  bufferSetUsage: (buffer, usage) => ggml_backend_buffer_set_usage(
    buffer,
    ggml_backend_buffer_usage.fromValue(usage),
  ),
  bufferFree: ggml_backend_buffer_free,
  tensorSet: ggml_backend_tensor_set,
  tensorGet: ggml_backend_tensor_get,
  schedNew: ggml_backend_sched_new,
  schedReset: ggml_backend_sched_reset,
  schedAllocGraph: ggml_backend_sched_alloc_graph,
  schedGraphCompute: (sched, graph) =>
      ggml_backend_sched_graph_compute(sched, graph).value,
  schedSynchronize: ggml_backend_sched_synchronize,
  schedFree: ggml_backend_sched_free,
);

final GgmlGraphApi _windowsApi = GgmlGraphApi._(
  init: _windowsInit,
  free: _windowsFree,
  tensorOverhead: _windowsTensorOverhead,
  graphOverheadCustom: _windowsGraphOverheadCustom,
  newTensor1d: _windowsNewTensor1d,
  newTensor2d: _windowsNewTensor2d,
  setInput: _windowsSetInput,
  setOutput: _windowsSetOutput,
  add: _windowsAdd,
  mul: _windowsMul,
  mulMat: _windowsMulMat,
  getRows: _windowsGetRows,
  norm: _windowsNorm,
  reshape3d: _windowsReshape3d,
  permute: _windowsPermute,
  softMaxExt: _windowsSoftMaxExt,
  cont: _windowsCont,
  cont2d: _windowsCont2d,
  transpose: _windowsTranspose,
  relu: _windowsRelu,
  geluErf: _windowsGeluErf,
  newGraphCustom: _windowsNewGraphCustom,
  buildForwardExpand: _windowsBuildForwardExpand,
  devByType: _windowsDevByType,
  devInit: _windowsDevInit,
  backendName: _windowsBackendName,
  backendGetDevice: _windowsBackendGetDevice,
  devBackendReg: _windowsDevBackendReg,
  regGetProcAddress: _windowsRegGetProcAddress,
  backendFree: _windowsBackendFree,
  allocCtxTensors: _windowsAllocCtxTensors,
  bufferSetUsage: _windowsBufferSetUsage,
  bufferFree: _windowsBufferFree,
  tensorSet: _windowsTensorSet,
  tensorGet: _windowsTensorGet,
  schedNew: _windowsSchedNew,
  schedReset: _windowsSchedReset,
  schedAllocGraph: _windowsSchedAllocGraph,
  schedGraphCompute: _windowsSchedGraphCompute,
  schedSynchronize: _windowsSchedSynchronize,
  schedFree: _windowsSchedFree,
);

const _llamadartAsset = 'package:llamadart/llamadart';
const _ggmlBaseAsset = 'package:llamadart/ggml-base';
const _ggmlAsset = 'package:llamadart/ggml';

@Native<ggml_backend_buffer_t Function(Pointer<ggml_context>, ggml_backend_t)>(
  assetId: _llamadartAsset,
  symbol: 'ggml_backend_alloc_ctx_tensors',
)
external ggml_backend_buffer_t _allocCtxTensors(
  Pointer<ggml_context> ctx,
  ggml_backend_t backend,
);

@Native<Pointer<ggml_context> Function(ggml_init_params)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_init',
)
external Pointer<ggml_context> _windowsInit(ggml_init_params params);

@Native<Void Function(Pointer<ggml_context>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_free',
)
external void _windowsFree(Pointer<ggml_context> ctx);

@Native<Size Function()>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_tensor_overhead',
)
external int _windowsTensorOverhead();

@Native<Size Function(Size, Bool)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_graph_overhead_custom',
)
external int _windowsGraphOverheadCustom(int size, bool grads);

@Native<
  Pointer<ggml_tensor> Function(Pointer<ggml_context>, UnsignedInt, Int64)
>(assetId: _ggmlBaseAsset, symbol: 'ggml_new_tensor_1d')
external Pointer<ggml_tensor> _windowsNewTensor1d(
  Pointer<ggml_context> ctx,
  int type,
  int ne0,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    UnsignedInt,
    Int64,
    Int64,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_new_tensor_2d')
external Pointer<ggml_tensor> _windowsNewTensor2d(
  Pointer<ggml_context> ctx,
  int type,
  int ne0,
  int ne1,
);

@Native<Void Function(Pointer<ggml_tensor>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_set_input',
)
external void _windowsSetInput(Pointer<ggml_tensor> tensor);

@Native<Void Function(Pointer<ggml_tensor>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_set_output',
)
external void _windowsSetOutput(Pointer<ggml_tensor> tensor);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Pointer<ggml_tensor>,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_add')
external Pointer<ggml_tensor> _windowsAdd(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  Pointer<ggml_tensor> b,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Pointer<ggml_tensor>,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_mul')
external Pointer<ggml_tensor> _windowsMul(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  Pointer<ggml_tensor> b,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Pointer<ggml_tensor>,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_mul_mat')
external Pointer<ggml_tensor> _windowsMulMat(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  Pointer<ggml_tensor> b,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Pointer<ggml_tensor>,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_get_rows')
external Pointer<ggml_tensor> _windowsGetRows(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  Pointer<ggml_tensor> b,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Float,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_norm')
external Pointer<ggml_tensor> _windowsNorm(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  double eps,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Int64,
    Int64,
    Int64,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_reshape_3d')
external Pointer<ggml_tensor> _windowsReshape3d(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  int ne0,
  int ne1,
  int ne2,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Int,
    Int,
    Int,
    Int,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_permute')
external Pointer<ggml_tensor> _windowsPermute(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  int axis0,
  int axis1,
  int axis2,
  int axis3,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Pointer<ggml_tensor>,
    Float,
    Float,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_soft_max_ext')
external Pointer<ggml_tensor> _windowsSoftMaxExt(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  Pointer<ggml_tensor> mask,
  double scale,
  double maxBias,
);

@Native<
  Pointer<ggml_tensor> Function(Pointer<ggml_context>, Pointer<ggml_tensor>)
>(assetId: _ggmlBaseAsset, symbol: 'ggml_cont')
external Pointer<ggml_tensor> _windowsCont(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
);

@Native<
  Pointer<ggml_tensor> Function(
    Pointer<ggml_context>,
    Pointer<ggml_tensor>,
    Int64,
    Int64,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_cont_2d')
external Pointer<ggml_tensor> _windowsCont2d(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
  int ne0,
  int ne1,
);

@Native<
  Pointer<ggml_tensor> Function(Pointer<ggml_context>, Pointer<ggml_tensor>)
>(assetId: _ggmlBaseAsset, symbol: 'ggml_transpose')
external Pointer<ggml_tensor> _windowsTranspose(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
);

@Native<
  Pointer<ggml_tensor> Function(Pointer<ggml_context>, Pointer<ggml_tensor>)
>(assetId: _ggmlBaseAsset, symbol: 'ggml_relu')
external Pointer<ggml_tensor> _windowsRelu(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
);

@Native<
  Pointer<ggml_tensor> Function(Pointer<ggml_context>, Pointer<ggml_tensor>)
>(assetId: _ggmlBaseAsset, symbol: 'ggml_gelu_erf')
external Pointer<ggml_tensor> _windowsGeluErf(
  Pointer<ggml_context> ctx,
  Pointer<ggml_tensor> a,
);

@Native<Pointer<ggml_cgraph> Function(Pointer<ggml_context>, Size, Bool)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_new_graph_custom',
)
external Pointer<ggml_cgraph> _windowsNewGraphCustom(
  Pointer<ggml_context> ctx,
  int size,
  bool grads,
);

@Native<Void Function(Pointer<ggml_cgraph>, Pointer<ggml_tensor>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_build_forward_expand',
)
external void _windowsBuildForwardExpand(
  Pointer<ggml_cgraph> graph,
  Pointer<ggml_tensor> tensor,
);

@Native<ggml_backend_dev_t Function(UnsignedInt)>(
  assetId: _ggmlAsset,
  symbol: 'ggml_backend_dev_by_type',
)
external ggml_backend_dev_t _windowsDevByType(int type);

@Native<ggml_backend_t Function(ggml_backend_dev_t, Pointer<Char>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_dev_init',
)
external ggml_backend_t _windowsDevInit(
  ggml_backend_dev_t device,
  Pointer<Char> params,
);

@Native<Pointer<Char> Function(ggml_backend_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_name',
)
external Pointer<Char> _windowsBackendName(ggml_backend_t backend);

@Native<ggml_backend_dev_t Function(ggml_backend_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_get_device',
)
external ggml_backend_dev_t _windowsBackendGetDevice(ggml_backend_t backend);

@Native<ggml_backend_reg_t Function(ggml_backend_dev_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_dev_backend_reg',
)
external ggml_backend_reg_t _windowsDevBackendReg(ggml_backend_dev_t device);

@Native<Pointer<Void> Function(ggml_backend_reg_t, Pointer<Char>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_reg_get_proc_address',
)
external Pointer<Void> _windowsRegGetProcAddress(
  ggml_backend_reg_t reg,
  Pointer<Char> name,
);

@Native<Void Function(ggml_backend_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_free',
)
external void _windowsBackendFree(ggml_backend_t backend);

@Native<ggml_backend_buffer_t Function(Pointer<ggml_context>, ggml_backend_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_alloc_ctx_tensors',
)
external ggml_backend_buffer_t _windowsAllocCtxTensors(
  Pointer<ggml_context> ctx,
  ggml_backend_t backend,
);

@Native<Void Function(ggml_backend_buffer_t, UnsignedInt)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_buffer_set_usage',
)
external void _windowsBufferSetUsage(ggml_backend_buffer_t buffer, int usage);

@Native<Void Function(ggml_backend_buffer_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_buffer_free',
)
external void _windowsBufferFree(ggml_backend_buffer_t buffer);

@Native<Void Function(Pointer<ggml_tensor>, Pointer<Void>, Size, Size)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_tensor_set',
)
external void _windowsTensorSet(
  Pointer<ggml_tensor> tensor,
  Pointer<Void> data,
  int offset,
  int size,
);

@Native<Void Function(Pointer<ggml_tensor>, Pointer<Void>, Size, Size)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_tensor_get',
)
external void _windowsTensorGet(
  Pointer<ggml_tensor> tensor,
  Pointer<Void> data,
  int offset,
  int size,
);

@Native<
  ggml_backend_sched_t Function(
    Pointer<ggml_backend_t>,
    Pointer<ggml_backend_buffer_type_t>,
    Int,
    Size,
    Bool,
    Bool,
  )
>(assetId: _ggmlBaseAsset, symbol: 'ggml_backend_sched_new')
external ggml_backend_sched_t _windowsSchedNew(
  Pointer<ggml_backend_t> backends,
  Pointer<ggml_backend_buffer_type_t> bufts,
  int count,
  int graphSize,
  bool parallel,
  bool opOffload,
);

@Native<Void Function(ggml_backend_sched_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_sched_reset',
)
external void _windowsSchedReset(ggml_backend_sched_t sched);

@Native<Bool Function(ggml_backend_sched_t, Pointer<ggml_cgraph>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_sched_alloc_graph',
)
external bool _windowsSchedAllocGraph(
  ggml_backend_sched_t sched,
  Pointer<ggml_cgraph> graph,
);

@Native<Int Function(ggml_backend_sched_t, Pointer<ggml_cgraph>)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_sched_graph_compute',
)
external int _windowsSchedGraphCompute(
  ggml_backend_sched_t sched,
  Pointer<ggml_cgraph> graph,
);

@Native<Void Function(ggml_backend_sched_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_sched_synchronize',
)
external void _windowsSchedSynchronize(ggml_backend_sched_t sched);

@Native<Void Function(ggml_backend_sched_t)>(
  assetId: _ggmlBaseAsset,
  symbol: 'ggml_backend_sched_free',
)
external void _windowsSchedFree(ggml_backend_sched_t sched);
