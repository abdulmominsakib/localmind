/// A model store shared by the llamadart apps that can open the same
/// directory.
library;

export 'src/model_store_entry.dart';
export 'src/model_store_stub.dart'
    if (dart.library.io) 'src/model_store_io.dart';
