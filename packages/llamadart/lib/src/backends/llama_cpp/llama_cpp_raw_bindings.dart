// coverage:ignore-file
// ignore_for_file: non_constant_identifier_names
@ffi.DefaultAsset('package:llamadart/llamadart')
library;

import 'dart:ffi' as ffi;

import 'bindings.dart';

/// Raw `llama_model_ftype` binding used to preserve unknown future ftype IDs.
@ffi.Native<ffi.UnsignedInt Function(ffi.Pointer<llama_model>)>(
  symbol: 'llama_model_ftype',
)
external int llama_model_ftype_raw(ffi.Pointer<llama_model> model);

/// Raw `llama_ftype_name` binding used with raw ftype IDs.
@ffi.Native<ffi.Pointer<ffi.Char> Function(ffi.UnsignedInt)>(
  symbol: 'llama_ftype_name',
)
external ffi.Pointer<ffi.Char> llama_ftype_name_raw(int ftype);
