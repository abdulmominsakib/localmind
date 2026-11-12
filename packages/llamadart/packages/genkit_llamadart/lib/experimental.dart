/// Opt-in experimental Genkit integrations for bounded local text sessions.
///
/// Import this separately from `genkit_llamadart.dart`. This surface depends on
/// Genkit Dart 1.0's experimental bidi protocol, which can change in minor
/// releases. Pin and qualify compatible Genkit versions before upgrading.
library;

export 'src/integration/genkit/bidi_plugin.dart' show LlamaDartBidiPlugin;
