/// Memory footprint measurement, absent on platforms without `dart:io`.
library;

export 'process_memory_stub.dart' if (dart.library.io) 'process_memory_io.dart';
