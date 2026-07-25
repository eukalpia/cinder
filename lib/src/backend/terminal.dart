import 'dart:convert';

import 'package:cinder/src/size.dart';
import 'package:cinder/src/style.dart';
import 'package:cinder/src/utils/escape_codes.dart';
import 'package:cinder/src/utils/terminal_text.dart';
import 'package:meta/meta.dart';

import 'terminal_backend.dart';

class Position {
  const Position(this.x, this.y);

  final int x;
  final int y;
}

/// A buffered terminal control surface backed by [TerminalBackend].
class Terminal {
  Terminal(this.backend, {Size? size}) {
    _size = size ?? backend.getSize();
  }

  final TerminalBackend backend;
  late Size _size;
  Stream<String>? _oscStream;

  /// Whether alternate screen mode is enabled.
  @protected
  bool altScreenEnabled = false;

  /// Write buffer for batching output.
  @protected
  final StringBuffer writeBuffer = StringBuffer();

  static const _rgbPattern =
      'rgb:([0-9a-fA-F]{4})/([0-9a-fA-F]{4})/([0-9a-fA-F]{4})';
  static final _bgRegexp = RegExp('11;$_rgbPattern');
  static final _fgRegexp = RegExp('10;$_rgbPattern');

  Size get size => _size;

  void updateSize(Size newSize) {
    _size = newSize;
  }

  void bindOSCStream(Stream<String> oscStream) {
    _oscStream = oscStream;
  }

  void enterAlternateScreen() {
    if (altScreenEnabled) return;
    flush();
    backend.writeRaw(EscapeCodes.alternateBuffer);
    clear();
    altScreenEnabled = true;
  }

  void leaveAlternateScreen() {
    if (!altScreenEnabled) return;
    flush();
    backend.writeRaw(EscapeCodes.mainBuffer);
    altScreenEnabled = false;
  }

  void hideCursor() {
    write(EscapeCodes.hideCursor);
  }

  void showCursor() {
    flush();
    backend.writeRaw(EscapeCodes.showCursor);
  }

  void clear() {
    write(EscapeCodes.clearScreen);
    write(EscapeCodes.moveCursorHome);
  }

  void clearLine() {
    write(EscapeCodes.clearLine);
  }

  void moveCursor(int x, int y) {
    write('\x1b[${y + 1};${x + 1}H');
  }

  void moveToHome() {
    write(EscapeCodes.moveCursorHome);
  }

  void moveTo(int x, int y) {
    moveCursor(x, y);
  }

  /// Writes trusted terminal control or already-sanitized application output.
  ///
  /// Prefer rendering untrusted text through widgets after applying
  /// [TerminalText.safe]. This method intentionally preserves escape sequences.
  void write(String text) {
    writeBuffer.write(text);
  }

  void flush() {
    if (writeBuffer.isEmpty) return;
    backend.writeRaw(writeBuffer.toString());
    writeBuffer.clear();
  }

  /// Sets the terminal foreground color.
  void setForeground(Color color) {
    write('\x1b]10;#');
    write(color.red.toRadixString(16).padLeft(2, '0'));
    write(color.green.toRadixString(16).padLeft(2, '0'));
    write(color.blue.toRadixString(16).padLeft(2, '0'));
    write('\x07');
  }

  /// Sets the terminal background color.
  void setBackground(Color color) {
    write('\x1b]11;#');
    write(color.red.toRadixString(16).padLeft(2, '0'));
    write(color.green.toRadixString(16).padLeft(2, '0'));
    write(color.blue.toRadixString(16).padLeft(2, '0'));
    write('\x07');
  }

  /// Reads the terminal's default foreground color.
  Future<Color?> getForegroundColor({
    Duration timeout = const Duration(milliseconds: 100),
  }) async {
    write('\x1b]10;?\x07');
    flush();
    return _oscStream
        ?.firstWhere(_fgRegexp.hasMatch)
        .timeout(timeout)
        .then(_parseForegroundResponse)
        .catchError((_) => null);
  }

  /// Reads the terminal's default background color.
  Future<Color?> getBackgroundColor({
    Duration timeout = const Duration(milliseconds: 100),
  }) async {
    write('\x1b]11;?\x07');
    flush();
    return _oscStream
        ?.firstWhere(_bgRegexp.hasMatch)
        .timeout(timeout)
        .then(_parseBackgroundResponse)
        .catchError((_) => null);
  }

  Color? _parseForegroundResponse(String event) {
    return _parseColorResponse(_fgRegexp, event);
  }

  Color? _parseBackgroundResponse(String event) {
    return _parseColorResponse(_bgRegexp, event);
  }

  Color? _parseColorResponse(RegExp expression, String event) {
    final match = expression.firstMatch(event);
    if (match == null) return null;
    return Color.fromRGB(
      int.parse(match.group(1)!, radix: 16) ~/ 256,
      int.parse(match.group(2)!, radix: 16) ~/ 256,
      int.parse(match.group(3)!, radix: 16) ~/ 256,
    );
  }

  /// Restores terminal foreground and background colors to their defaults.
  void restoreColors() {
    backend.writeRaw('\x1b]110\x07');
    backend.writeRaw('\x1b]111\x07');
  }

  /// Restores terminal state owned by this instance.
  void reset() {
    showCursor();
    restoreColors();
    leaveAlternateScreen();
    backend.writeRaw('\x1b[0m');
  }

  /// Writes an OSC 52 clipboard sequence.
  ///
  /// The payload is base64-encoded, so text cannot terminate the OSC sequence.
  void writeClipboardCopy(String text) {
    final base64Text = base64Encode(utf8.encode(text));
    write('\x1b]52;c;$base64Text\x07');
  }

  /// Sets the terminal window title using OSC 2.
  ///
  /// Control characters and nested escape sequences are always removed, even
  /// when this low-level method is called directly.
  void setWindowTitle(String title) {
    write('\x1b]2;${_sanitizeOscMetadata(title)}\x07');
  }

  /// Sets the terminal icon name using OSC 1.
  void setIconName(String name) {
    write('\x1b]1;${_sanitizeOscMetadata(name)}\x07');
  }

  /// Sets both terminal window title and icon name using OSC 0.
  void setTitleAndIcon(String text) {
    write('\x1b]0;${_sanitizeOscMetadata(text)}\x07');
  }

  String _sanitizeOscMetadata(String value) {
    return TerminalText.safe(
      value,
      preserveNewlines: false,
      preserveTabs: false,
    );
  }

  /// Writes a pre-encoded inline image protocol sequence at a cell position.
  ///
  /// [encodedData] is trusted protocol data and must never be populated from
  /// arbitrary process or network output.
  void writeInlineImage(String encodedData, int x, int y) {
    moveCursor(x, y);
    write(encodedData);
  }

  /// Backwards-compatible Sixel-specific name.
  void writeSixel(String sixelData, int x, int y) {
    writeInlineImage(sixelData, x, y);
  }
}
