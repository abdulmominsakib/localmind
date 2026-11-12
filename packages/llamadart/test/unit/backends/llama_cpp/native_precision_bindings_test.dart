@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:test/test.dart';

void main() {
  test('v0.4.1 precision bindings preserve accepted and unsupported paths', () {
    // @Native resolves the emitted code asset; DynamicLibrary.open accepts
    // filesystem paths and cannot resolve package asset identifiers.
    final init = Platform.isWindows ? _splitInit : ggml_init;
    final free = Platform.isWindows ? _splitFree : ggml_free;
    final newTensor = Platform.isWindows
        ? _splitNewTensor
        : (ffi.Pointer<ggml_context> ctx, int type, int x, int y) =>
              ggml_new_tensor_2d(ctx, ggml_type.fromValue(type), x, y);
    final multiply = Platform.isWindows ? _splitMultiply : ggml_mul_mat;
    final setAccumulator = Platform.isWindows
        ? _splitSetAccumulator
        : (ffi.Pointer<ggml_tensor> tensor, int precision) =>
              ggml_prec_set_acc(tensor, ggml_prec.fromValue(precision));
    final setSource = Platform.isWindows
        ? _splitSetSource
        : (ffi.Pointer<ggml_tensor> tensor, int precision, int index) =>
              ggml_prec_set_src(tensor, ggml_prec.fromValue(precision), index);
    final params = calloc<ggml_init_params>();
    addTearDown(() => calloc.free(params));
    params.ref
      ..mem_size = 1024 * 1024
      ..mem_buffer = ffi.nullptr
      ..no_alloc = true;
    final context = init(params.ref);
    expect(context, isNot(ffi.nullptr));
    addTearDown(() => free(context));

    final lhs = newTensor(context, ggml_type.GGML_TYPE_F32.value, 32, 2);
    final rhs = newTensor(context, ggml_type.GGML_TYPE_F32.value, 32, 1);
    final product = multiply(context, lhs, rhs);
    expect(setAccumulator(product, ggml_prec.GGML_PREC_F32.value), isTrue);
    expect(product.ref.op_params[0], ggml_prec.GGML_PREC_F32.value);
    expect(setSource(product, ggml_prec.GGML_PREC_F16.value, 1), isTrue);
    expect(product.ref.op_params[3], ggml_prec.GGML_PREC_F16.value);
    expect(setSource(product, ggml_prec.GGML_PREC_Q8.value, 0), isFalse);
    expect(product.ref.op_params[3], ggml_prec.GGML_PREC_F16.value);
    expect(setAccumulator(lhs, ggml_prec.GGML_PREC_F32.value), isFalse);
    expect(setSource(lhs, ggml_prec.GGML_PREC_F16.value, 1), isFalse);
    expect(ggml_prec.GGML_PREC_DEFAULT, ggml_prec.GGML_PREC_UNDEFINED);
    expect(ggml_prec.fromValue(40), ggml_prec.GGML_PREC_Q4);
  });
}

// Windows exports these operations from the GGML dependency DLL, not the
// primary llamadart DLL. Keep the hook's native asset identity explicit.
const _ggmlAsset = 'package:llamadart/ggml-base';

@ffi.Native<ffi.Pointer<ggml_context> Function(ggml_init_params)>(
  assetId: _ggmlAsset,
  symbol: 'ggml_init',
)
external ffi.Pointer<ggml_context> _splitInit(ggml_init_params params);

@ffi.Native<ffi.Void Function(ffi.Pointer<ggml_context>)>(
  assetId: _ggmlAsset,
  symbol: 'ggml_free',
)
external void _splitFree(ffi.Pointer<ggml_context> context);

@ffi.Native<
  ffi.Pointer<ggml_tensor> Function(
    ffi.Pointer<ggml_context>,
    ffi.UnsignedInt,
    ffi.Int64,
    ffi.Int64,
  )
>(assetId: _ggmlAsset, symbol: 'ggml_new_tensor_2d')
external ffi.Pointer<ggml_tensor> _splitNewTensor(
  ffi.Pointer<ggml_context> context,
  int type,
  int x,
  int y,
);

@ffi.Native<
  ffi.Pointer<ggml_tensor> Function(
    ffi.Pointer<ggml_context>,
    ffi.Pointer<ggml_tensor>,
    ffi.Pointer<ggml_tensor>,
  )
>(assetId: _ggmlAsset, symbol: 'ggml_mul_mat')
external ffi.Pointer<ggml_tensor> _splitMultiply(
  ffi.Pointer<ggml_context> context,
  ffi.Pointer<ggml_tensor> lhs,
  ffi.Pointer<ggml_tensor> rhs,
);

@ffi.Native<ffi.Bool Function(ffi.Pointer<ggml_tensor>, ffi.UnsignedInt)>(
  assetId: _ggmlAsset,
  symbol: 'ggml_prec_set_acc',
)
external bool _splitSetAccumulator(
  ffi.Pointer<ggml_tensor> tensor,
  int precision,
);

@ffi.Native<
  ffi.Bool Function(ffi.Pointer<ggml_tensor>, ffi.UnsignedInt, ffi.Int)
>(assetId: _ggmlAsset, symbol: 'ggml_prec_set_src')
external bool _splitSetSource(
  ffi.Pointer<ggml_tensor> tensor,
  int precision,
  int index,
);
