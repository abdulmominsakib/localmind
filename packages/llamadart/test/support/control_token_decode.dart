/// Splits [output] into the token pieces a llama.cpp backend yields when every
/// `<|NAME|>` marker in it is one control token, as GGUF conversion marks
/// Cohere's added tokens.
///
/// llama.cpp decodes a control token as empty text unless it is decoded as
/// special, which the llama.cpp backend does only for [preservedTokens].
List<String> decodeControlMarkedPieces(
  String output, {
  required List<String> preservedTokens,
}) {
  final pieces = <String>[];
  var cursor = 0;
  for (final marker in RegExp(r'<\|[A-Z_]+\|>').allMatches(output)) {
    if (marker.start > cursor) {
      pieces.add(output.substring(cursor, marker.start));
    }
    final text = marker[0]!;
    pieces.add(preservedTokens.contains(text) ? text : '');
    cursor = marker.end;
  }
  if (cursor < output.length) {
    pieces.add(output.substring(cursor));
  }
  return pieces;
}
