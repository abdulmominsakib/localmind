import 'package:llamadart/llamadart.dart';
import 'package:llamadart_model_store/llamadart_model_store.dart';

/// Releases the entry `args[2]` for the app `args[1]` from the store in
/// `args[0]`, as another process of that app would.
Future<void> main(List<String> args) async {
  final store = await ModelStore.open(directory: args[0], appId: args[1]);
  try {
    await store.release(args[2]);
  } on ModelCacheEntryInUseException {
    // The reference is dropped; the files are downloading in the test.
  }
}
