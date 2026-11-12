import '../exceptions.dart';
import 'runtime_setup_report.dart';

/// The common/Web collector rejects hosts outside the desktop IO scope.
Future<LlamaRuntimeSetupReport>
collectRuntimeSetupReport() async => throw LlamaUnsupportedException(
  'Runtime setup reports require a macOS, Linux or Windows Dart IO process. '
  'Web and mobile require separate app/device/browser validation; '
  'web_setup --check only checks Web assets.',
);
