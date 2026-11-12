import 'dart:typed_data';

/// Reads [length] bytes of the projector file at [location] from [offset].
///
/// Without `dart:io`, as on the web, there is no local file to read, so this
/// always throws [UnsupportedError].
Uint8List readProjectorFileRange(String location, int offset, int length) =>
    throw UnsupportedError('Projector files cannot be read on this platform.');
