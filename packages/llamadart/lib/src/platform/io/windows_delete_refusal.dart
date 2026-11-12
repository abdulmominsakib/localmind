import 'dart:io';

/// `ERROR_SHARING_VIOLATION`, `ERROR_LOCK_VIOLATION` and
/// `ERROR_USER_MAPPED_FILE`: Windows refuses an operation on a file another
/// handle has open, locked or mapped.
const Set<int> windowsFileInUseErrors = <int>{32, 33, 1224};

const int _windowsErrorAccessDenied = 5;

/// Whether Windows refused to delete [file] with [errorCode] because a
/// process has it open or mapped, rather than for good.
///
/// `ERROR_ACCESS_DENIED` (5) reports both a mapped file, such as a loaded
/// model, and a permanent denial such as a read-only file or an ACL, so it
/// counts as in use only when opening [file] for writing succeeds or fails
/// with a sharing or lock violation. A denial of delete access alone, on a
/// file that can still be written, stays indistinguishable and counts as in
/// use.
Future<bool> isWindowsDeleteRefusedForOpenFile(
  File file,
  int? errorCode,
) async {
  if (windowsFileInUseErrors.contains(errorCode)) {
    return true;
  }
  if (errorCode != _windowsErrorAccessDenied) {
    return false;
  }
  try {
    final handle = await file.open(mode: FileMode.append);
    await handle.close();
    return true;
  } on FileSystemException catch (error) {
    return windowsFileInUseErrors.contains(error.osError?.errorCode);
  }
}
