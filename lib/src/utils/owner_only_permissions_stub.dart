/// Restricts [path] so that only its owner can access it.
///
/// Local files are unavailable on this platform.
void restrictToOwner(String path, {required bool directory}) {
  throw UnsupportedError('File permissions are unavailable on this platform');
}
