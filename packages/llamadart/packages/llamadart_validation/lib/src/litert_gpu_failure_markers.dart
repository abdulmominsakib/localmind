/// Log text by which LiteRT reports a GPU delegate failure or CPU fallback.
/// Not exhaustive.
const liteRtGpuFailureMarkers = [
  'GPU accelerator could not be loaded and registered',
  'Some ops are not accelerated',
  'Failed to modify graph with delegate',
  'VK_ERROR_',
  'Validation error',
  'Falling back to CPU',
];

/// Whether [text] carries one of the markers by which a LiteRT GPU log
/// reports a delegate failure or CPU fallback.
bool containsLiteRtGpuFailureMarker(String text) {
  final lowered = text.toLowerCase();
  return liteRtGpuFailureMarkers.any(
    (marker) => lowered.contains(marker.toLowerCase()),
  );
}
