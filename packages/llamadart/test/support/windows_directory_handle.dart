import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Marks the empty Windows directory [directoryPath] for deletion and keeps
/// it pending delete until the returned function closes the handle, which
/// completes the deletion.
///
/// This is the state a directory is in while another process deletes it:
/// between setting the delete disposition and closing its handle, opening the
/// directory fails with `ERROR_ACCESS_DENIED`. A handle opened without delete
/// access does not cause it where Windows deletes with POSIX semantics, as on
/// NTFS since Windows 10: the name disappears at once.
void Function() markWindowsDirectoryDeletePending(String directoryPath) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final createFile = kernel32
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  final setFileInformationByHandle = kernel32
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32),
        int Function(int, int, Pointer<Uint8>, int)
      >('SetFileInformationByHandle');
  final closeHandle = kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  const delete = 0x10000;
  const shareReadWriteDelete = 0x7;
  const openExisting = 3;
  const fileFlagBackupSemantics = 0x02000000;
  const invalidHandleValue = -1;
  const fileDispositionInfo = 4;

  final pathPointer = directoryPath.toNativeUtf16();
  final int handle;
  try {
    handle = createFile(
      pathPointer,
      delete,
      shareReadWriteDelete,
      nullptr,
      openExisting,
      fileFlagBackupSemantics,
      0,
    );
  } finally {
    calloc.free(pathPointer);
  }
  if (handle == invalidHandleValue) {
    throw StateError('CreateFileW failed to open $directoryPath');
  }
  final deleteFile = calloc<Uint8>()..value = 1;
  try {
    if (setFileInformationByHandle(
          handle,
          fileDispositionInfo,
          deleteFile,
          1,
        ) ==
        0) {
      closeHandle(handle);
      throw StateError('Cannot mark $directoryPath for deletion');
    }
  } finally {
    calloc.free(deleteFile);
  }
  var closed = false;
  return () {
    if (!closed) {
      closed = true;
      closeHandle(handle);
    }
  };
}
