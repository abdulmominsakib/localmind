import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';

import '../../support/slow_exiting_worker.dart';

Future<void> main() async {
  final backend = NativeLlamaBackend(workerEntrypoint: slowExitingWorkerEntry);
  await backend.modelLoad('model.gguf', const ModelParams());
  await backend.dispose();
  print('DISPOSAL_COMPLETED');
}
