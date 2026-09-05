import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_pty_process.dart';

/// Windows 10 1809+ ConPTY. Handles stay owned until output and writes finish.
class WindowsNativePty implements NativePtyProcess {
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _createPipe = _kernel
      .lookupFunction<
        Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
        int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
      >('CreatePipe');
  static final _createConsole = _kernel
      .lookupFunction<
        Int32 Function(_Coord, IntPtr, IntPtr, Uint32, Pointer<IntPtr>),
        int Function(_Coord, int, int, int, Pointer<IntPtr>)
      >('CreatePseudoConsole');
  static final _resizeConsole = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, _Coord),
        int Function(int, _Coord)
      >('ResizePseudoConsole');
  static final _closeConsole = _kernel
      .lookupFunction<Void Function(IntPtr), void Function(int)>(
        'ClosePseudoConsole',
      );
  static final _initAttributes = _kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<IntPtr>),
        int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
      >('InitializeProcThreadAttributeList');
  static final _updateAttributes = _kernel
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Uint32,
          IntPtr,
          Pointer<Void>,
          IntPtr,
          Pointer<Void>,
          Pointer<IntPtr>,
        ),
        int Function(
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
          int,
          Pointer<Void>,
          Pointer<IntPtr>,
        )
      >('UpdateProcThreadAttribute');
  static final _deleteAttributes = _kernel
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('DeleteProcThreadAttributeList');
  static final _createProcess = _kernel
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Void>,
          Pointer<Void>,
          Int32,
          Uint32,
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<_StartupInfoEx>,
          Pointer<_ProcessInformation>,
        ),
        int Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Void>,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<_StartupInfoEx>,
          Pointer<_ProcessInformation>,
        )
      >('CreateProcessW');
  static final _closeHandle = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  static final _peek = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Void>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('PeekNamedPipe');
  static final _read = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  static final _write = _kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('WriteFile');
  static final _wait = _kernel
      .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject',
      );
  static final _exit = _kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetExitCodeProcess');
  static final _terminate = _kernel
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'TerminateProcess',
      );
  static final _lastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  @override
  final int pid;
  final int _process;
  final int _console;
  final int _input;
  final int _output;
  final _buffer = calloc<Uint8>(65536);
  final _count = calloc<Uint32>();
  int? _exitCode;
  bool _closed = false;
  bool _acceptWrites = true;
  Future<void>? _finishing;

  WindowsNativePty._(
    this.pid,
    this._process,
    this._console,
    this._input,
    this._output,
  );

  static WindowsNativePty start(
    String command,
    List<String> arguments,
    String? directory,
    Map<String, String> environment,
    int rows,
    int columns,
  ) {
    // Resolve the symbol before creating handles: old Windows installations
    // fail explicitly instead of silently falling back to redirected pipes.
    final createConsole = _createConsole;
    return using((arena) {
      final inputRead = arena<IntPtr>();
      final inputWrite = arena<IntPtr>();
      final outputRead = arena<IntPtr>();
      final outputWrite = arena<IntPtr>();
      final console = arena<IntPtr>();
      final info = arena<_ProcessInformation>();
      var success = false;
      try {
        _check(
          _createPipe(inputRead, inputWrite, nullptr, 0),
          'CreatePipe(input)',
        );
        _check(
          _createPipe(outputRead, outputWrite, nullptr, 0),
          'CreatePipe(output)',
        );
        final size = arena<_Coord>()..ref.x = columns;
        size.ref.y = rows;
        _checkResult(
          createConsole(
            size.ref,
            inputRead.value,
            outputWrite.value,
            0,
            console,
          ),
          'CreatePseudoConsole',
        );
        final attributeSize = arena<IntPtr>();
        _initAttributes(nullptr, 1, 0, attributeSize);
        final attributes = arena<Uint8>(attributeSize.value).cast<Void>();
        _check(
          _initAttributes(attributes, 1, 0, attributeSize),
          'InitializeProcThreadAttributeList',
        );
        try {
          _check(
            _updateAttributes(
              attributes,
              0,
              0x00020016,
              Pointer<Void>.fromAddress(console.value),
              sizeOf<IntPtr>(),
              nullptr,
              nullptr,
            ),
            'UpdateProcThreadAttribute',
          );
          final startup = arena<_StartupInfoEx>();
          startup.ref.info.cb = sizeOf<_StartupInfoEx>();
          // Suppress Windows' implicit duplication of redirected parent stdio.
          // Null standard handles let ConPTY create the child's console handles.
          // https://github.com/microsoft/terminal/discussions/15814
          startup.ref.info.flags = 0x00000100; // STARTF_USESTDHANDLES
          startup.ref.attributes = attributes;
          final entries =
              normalizeWindowsEnvironment(environment).entries.toList()..sort(
                (a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()),
              );
          final environmentBlock =
              '${entries.map((entry) => '${entry.key}=${entry.value}').join('\x00')}\x00\x00';
          final commandLine = [
            command,
            ...arguments,
          ].map(quoteWindowsArgument).join(' ');
          _check(
            _createProcess(
              nullptr,
              commandLine.toNativeUtf16(allocator: arena),
              nullptr,
              nullptr,
              0,
              0x00080000 | 0x00000400,
              environmentBlock.toNativeUtf16(allocator: arena).cast(),
              directory?.toNativeUtf16(allocator: arena) ?? nullptr,
              startup,
              info,
            ),
            command,
            arguments,
          );
        } finally {
          _deleteAttributes(attributes);
        }
        success = true;
        return WindowsNativePty._(
          info.ref.pid,
          info.ref.process,
          console.value,
          inputWrite.value,
          outputRead.value,
        );
      } finally {
        if (inputRead.value != 0) _closeHandle(inputRead.value);
        if (outputWrite.value != 0) _closeHandle(outputWrite.value);
        if (info.ref.thread != 0) _closeHandle(info.ref.thread);
        if (!success) {
          if (console.value != 0) _closeConsole(console.value);
          if (inputWrite.value != 0) _closeHandle(inputWrite.value);
          if (outputRead.value != 0) _closeHandle(outputRead.value);
          if (info.ref.process != 0) _closeHandle(info.ref.process);
        }
      }
    });
  }

  static void _check(
    int result,
    String operation, [
    List<String> arguments = const [],
  ]) {
    if (result == 0) {
      throw ProcessException(
        operation,
        arguments,
        'Windows error ${_lastError()}',
        _lastError(),
      );
    }
  }

  static void _checkResult(int result, String operation) {
    if (result < 0) {
      throw ProcessException(
        operation,
        const [],
        'HRESULT 0x${result.toUnsigned(32).toRadixString(16)}',
        result,
      );
    }
  }

  @override
  Uint8List? read() {
    if (_closed) return Uint8List(0);
    if (_peek(_output, nullptr, 0, nullptr, _count, nullptr) == 0) {
      final error = _lastError();
      if (error == 109 || error == 232) {
        return Uint8List(0); // broken/no-data pipe
      }
      throw ProcessException(
        'PeekNamedPipe',
        const [],
        'Windows error $error',
        error,
      );
    }
    if (_count.value == 0) return null;
    final available = _count.value.clamp(0, 65536);
    _check(
      _read(_output, _buffer, available, _count, nullptr),
      'ReadFile(pty)',
    );
    return Uint8List.fromList(_buffer.asTypedList(_count.value));
  }

  @override
  Future<void> write(Uint8List bytes) {
    if (_closed || !_acceptWrites) {
      return Future.error(StateError('PTY is closed'));
    }
    final handle = _input;
    // Anonymous ConPTY pipes require synchronous writes. Keep a blocked write
    // off the UI isolate, which must continue draining the output pipe.
    return Isolate.run(() => _writeBytes(handle, bytes));
  }

  @override
  void stopWriting() => _acceptWrites = false;

  static void _writeBytes(int handle, Uint8List bytes) {
    using((arena) {
      final buffer = arena<Uint8>(bytes.length);
      final count = arena<Uint32>();
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        _check(
          _write(
            handle,
            buffer + offset,
            bytes.length - offset,
            count,
            nullptr,
          ),
          'WriteFile(pty)',
        );
        if (count.value == 0) throw StateError('PTY input closed');
        offset += count.value;
      }
    });
  }

  @override
  int? pollExit() {
    if (_closed || _exitCode != null) return _exitCode;
    final state = _wait(_process, 0);
    if (state == 0) {
      _check(_exit(_process, _count), 'GetExitCodeProcess');
      _exitCode = _count.value;
    } else if (state == 0xffffffff) {
      _check(0, 'WaitForSingleObject');
    }
    return _exitCode;
  }

  @override
  void resize(int rows, int columns) {
    using((arena) {
      final size = arena<_Coord>();
      size.ref.x = columns;
      size.ref.y = rows;
      _checkResult(_resizeConsole(_console, size.ref), 'ResizePseudoConsole');
    });
  }

  @override
  bool kill(ProcessSignal signal) =>
      !_closed && _exitCode == null && _terminate(_process, 1) != 0;

  @override
  Future<void> finish() {
    final console = _console;
    // ClosePseudoConsole can flush output and block until it is consumed.
    // The caller keeps pumping reads while this separate isolate closes it.
    return _finishing ??= Isolate.run(() => _closeConsole(console));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await finish();
    _closed = true;
    _closeHandle(_input);
    _closeHandle(_output);
    _closeHandle(_process);
    calloc.free(_buffer);
    calloc.free(_count);
  }
}

/// Microsoft CRT argv quoting, including empty arguments and trailing slashes.
String quoteWindowsArgument(String argument) {
  final result = StringBuffer('"');
  var slashes = 0;
  for (final code in argument.codeUnits) {
    if (code == 92) {
      slashes++;
      continue;
    }
    if (code == 34) {
      result.write('\\' * (slashes * 2 + 1));
    } else {
      result.write('\\' * slashes);
    }
    slashes = 0;
    result.writeCharCode(code);
  }
  result.write('\\' * (slashes * 2));
  result.write('"');
  return result.toString();
}

final class _Coord extends Struct {
  @Int16()
  external int x;
  @Int16()
  external int y;
}

final class _StartupInfo extends Struct {
  @Uint32()
  external int cb;
  external Pointer<Utf16> reserved;
  external Pointer<Utf16> desktop;
  external Pointer<Utf16> title;
  @Uint32()
  external int x;
  @Uint32()
  external int y;
  @Uint32()
  external int xSize;
  @Uint32()
  external int ySize;
  @Uint32()
  external int xCountChars;
  @Uint32()
  external int yCountChars;
  @Uint32()
  external int fillAttribute;
  @Uint32()
  external int flags;
  @Uint16()
  external int showWindow;
  @Uint16()
  external int reservedBytes;
  external Pointer<Uint8> reserved2;
  @IntPtr()
  external int stdin;
  @IntPtr()
  external int stdout;
  @IntPtr()
  external int stderr;
}

final class _StartupInfoEx extends Struct {
  external _StartupInfo info;
  external Pointer<Void> attributes;
}

final class _ProcessInformation extends Struct {
  @IntPtr()
  external int process;
  @IntPtr()
  external int thread;
  @Uint32()
  external int pid;
  @Uint32()
  external int tid;
}

/// Windows names are case-insensitive; later caller overrides must win even
/// when their spelling differs from Platform.environment's uppercase keys.
Map<String, String> normalizeWindowsEnvironment(
  Map<String, String> environment,
) => {
  for (final entry in environment.entries) entry.key.toUpperCase(): entry.value,
};
