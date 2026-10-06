// Native platforms restrict files with chmod; web never publishes local files.
export 'owner_only_permissions_stub.dart'
    if (dart.library.ffi) 'owner_only_permissions_ffi.dart';
