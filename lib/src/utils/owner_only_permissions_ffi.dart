import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// mode_t is 16 bits on Darwin and 32 bits on Linux.
final int Function(Pointer<Utf8>, int) _chmod =
    Platform.isMacOS || Platform.isIOS
    ? DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint16),
        int Function(Pointer<Utf8>, int)
      >('chmod')
    : DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');

/// Restricts [path] so that only its owner can access it: mode `0700` for a
/// directory and `0600` for a file.
///
/// The resulting mode is verified, so file systems that ignore `chmod` are
/// reported rather than trusted. Windows user profiles are private to their
/// owner by default and are left unchanged.
///
/// Throws a [FileSystemException] when the permissions cannot be restricted.
void restrictToOwner(String path, {required bool directory}) {
  if (Platform.isWindows) return;
  final mode = directory ? 0x1c0 : 0x180; // 0700 : 0600
  final nativePath = path.toNativeUtf8();
  try {
    if (_chmod(nativePath, mode) != 0) {
      throw FileSystemException('Could not restrict permissions', path);
    }
  } finally {
    malloc.free(nativePath);
  }
  // Group and other permission bits must all be clear.
  if (FileStat.statSync(path).mode & 0x3f != 0) {
    throw FileSystemException('File system ignored permission change', path);
  }
}
