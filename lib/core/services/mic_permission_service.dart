import 'package:permission_handler/permission_handler.dart';

/// Owns the RECORD_AUDIO runtime permission decision. Abstracted so tests
/// can substitute a stub and so device-specific quirks (e.g. Samsung One UI
/// recognizers reporting permission errors after a granted dialog) can be
/// resolved against the real permission state instead of plugin guesses.
abstract class MicPermissionClient {
  Future<bool> isGranted();

  Future<bool> isPermanentlyDenied();

  Future<bool> request();
}

class MicPermissionClientImpl implements MicPermissionClient {
  const MicPermissionClientImpl();

  @override
  Future<bool> isGranted() {
    return Permission.microphone.isGranted;
  }

  @override
  Future<bool> isPermanentlyDenied() {
    return Permission.microphone.isPermanentlyDenied;
  }

  @override
  Future<bool> request() {
    return Permission.microphone.request().then((status) => status.isGranted);
  }
}
