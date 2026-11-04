// coverage:ignore-file
// ignore_for_file: public_member_api_docs, non_constant_identifier_names
// Stub file for web/WASM analysis where dart:ffi is not available.
//
// Keep these signatures free of dart:ffi types so pub.dev/pana can analyze the
// default conditional-export branch without selecting native bindings. The VM
// still selects bindings.dart through the dart.library.io conditional export.

void llama_backend_init() => throw UnsupportedError(
  'llama_backend_init is only available on native platforms.',
);

void llama_backend_free() => throw UnsupportedError(
  'llama_backend_free is only available on native platforms.',
);

dynamic llama_print_system_info() => throw UnsupportedError(
  'llama_print_system_info is only available on native platforms.',
);

void llama_dart_set_log_level(int level) => throw UnsupportedError(
  'llama_dart_set_log_level is only available on native platforms.',
);
