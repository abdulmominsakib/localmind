import 'package:llamadart/llamadart.dart';
import 'package:llamadart_model_store/llamadart_model_store.dart';

/// Ensures, from the cache only, the model at the URL `args[2]` for the app `args[1]` in the
/// store in `args[0]`, as another process of that app would.
Future<void> main(List<String> args) async {
  final store = await ModelStore.open(directory: args[0], appId: args[1]);
  await store.ensure(
    LlamaModel(ModelSource.url(Uri.parse(args[2]))),
    options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
  );
}
