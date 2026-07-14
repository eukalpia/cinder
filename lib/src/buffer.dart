import 'dart:collection';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:cinder/src/rectangle.dart';

import 'style.dart';
import 'utils/unicode_width.dart';

/// A mutable terminal cell reused across frames.
///
/// Cinder deliberately mutates existing cells instead of allocating a new
/// object for every painted terminal position on every frame.
class Cell {
  Cell({
    this.char = ' ',
    TextStyle? style,
    this.isImagePlaceholder = false,
  }) : style = style ?? const TextStyle();

  String char;
  TextStyle style;
  bool isImagePlaceholder;

  int? _cachedWidth;

  int get width {
    _cachedWidth ??= UnicodeWidth.graphemeWidth(char);
    return _cachedWidth!;
  }

  bool get isDefault =>
      char == ' ' && style == const TextStyle() && !isImagePlaceholder;

  void set({
    required String char,
    required TextStyle style,
    bool isImagePlaceholder = false,
  }) {
    if (this.char != char) {
      this.char = char;
      _cachedWidth = null;
    }
    this.style = style;
    this.isImagePlaceholder = isImagePlaceholder;
  }

  void copyFrom(Cell other) {
    set(
      char: other.char,
      style: other.style,
      isImagePlaceholder: other.isImagePlaceholder,
    );
  }

  void reset() {
    if (char != ' ') {
      char = ' ';
      _cachedWidth = 1;
    }
    style = const TextStyle();
    isImagePlaceholder = false;
  }

  Cell copyWith({String? char, TextStyle? style, bool? isImagePlaceholder}) {
    return Cell(
      char: char ?? this.char,
      style: style ?? this.style,
      isImagePlaceholder: isImagePlaceholder ?? this.isImagePlaceholder,
    );
  }

  bool matches(Cell other) {
    return identical(this, other) ||
        (char == other.char &&
            style == other.style &&
            isImagePlaceholder == other.isImagePlaceholder);
  }

  @override
  bool operator ==(Object other) => other is Cell && matches(other);

  @override
  int get hashCode => Object.hash(char, style, isImagePlaceholder);
}

class PendingImage {
  const PendingImage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.sixelData,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final String sixelData;
}

/// A reusable, flat terminal frame buffer with per-row dirty spans.
///
/// The old renderer allocated `List<List<Cell>>` and a new [Cell] for every
/// terminal position on every frame. This implementation allocates its storage
/// once, reuses cells, and records only the horizontal span touched on each row.
class Buffer {
  Buffer(this.width, this.height)
      : _flatCells = List<Cell>.generate(
          width * height,
          (_) => Cell(),
          growable: false,
        ),
        _dirtyStart = Int32List(height),
        _dirtyEnd = Int32List(height) {
    for (var y = 0; y < height; y++) {
      _dirtyStart[y] = width;
      _dirtyEnd[y] = -1;
    }
    cells = List<List<Cell>>.generate(
      height,
      (y) => _CellRow(this, y),
      growable: false,
    );
  }

  final int width;
  final int height;
  final List<Cell> _flatCells;
  final Int32List _dirtyStart;
  final Int32List _dirtyEnd;

  /// Compatibility row views backed by the flat cell storage.
  late final List<List<Cell>> cells;

  final List<PendingImage> pendingImages = <PendingImage>[];

  static final Cell _outOfBoundsCell = Cell();

  int _index(int x, int y) => y * width + x;

  bool contains(int x, int y) =>
      x >= 0 && x < width && y >= 0 && y < height;

  Cell getCell(int x, int y) {
    if (!contains(x, y)) return _outOfBoundsCell;
    return _flatCells[_index(x, y)];
  }

  void setCell(int x, int y, Cell cell) {
    if (!contains(x, y)) return;
    final target = _flatCells[_index(x, y)];
    target.copyFrom(cell);
    markDirtyCell(x, y);
  }

  /// Writes directly into a reusable cell without allocating a temporary Cell.
  void writeCell(
    int x,
    int y, {
    required String char,
    TextStyle style = const TextStyle(),
    bool isImagePlaceholder = false,
  }) {
    if (!contains(x, y)) return;
    _flatCells[_index(x, y)].set(
      char: char,
      style: style,
      isImagePlaceholder: isImagePlaceholder,
    );
    markDirtyCell(x, y);
  }

  void markDirtyCell(int x, int y) {
    if (!contains(x, y)) return;
    if (x < _dirtyStart[y]) _dirtyStart[y] = x;
    if (x > _dirtyEnd[y]) _dirtyEnd[y] = x;
  }

  void markDirtyRect(int left, int top, int right, int bottom) {
    final clippedLeft = left.clamp(0, width);
    final clippedRight = right.clamp(0, width);
    final clippedTop = top.clamp(0, height);
    final clippedBottom = bottom.clamp(0, height);
    if (clippedLeft >= clippedRight || clippedTop >= clippedBottom) return;

    for (var y = clippedTop; y < clippedBottom; y++) {
      if (clippedLeft < _dirtyStart[y]) _dirtyStart[y] = clippedLeft;
      final end = clippedRight - 1;
      if (end > _dirtyEnd[y]) _dirtyEnd[y] = end;
    }
  }

  bool isRowDirty(int y) =>
      y >= 0 && y < height && _dirtyEnd[y] >= _dirtyStart[y];

  int dirtyStartForRow(int y) => _dirtyStart[y];
  int dirtyEndForRow(int y) => _dirtyEnd[y];

  int get dirtyCellUpperBound {
    var total = 0;
    for (var y = 0; y < height; y++) {
      if (isRowDirty(y)) total += _dirtyEnd[y] - _dirtyStart[y] + 1;
    }
    return total;
  }

  void setString(int x, int y, String text, {TextStyle? style}) {
    var currentX = x;
    final effectiveStyle = style ?? const TextStyle();

    for (final grapheme in text.characters) {
      if (currentX >= width) break;
      final charWidth = UnicodeWidth.graphemeWidth(grapheme);
      if (charWidth == 0) continue;
      if (charWidth == 2 && currentX + 1 >= width) break;

      if (y >= 0 && y < height && currentX >= 0) {
        writeCell(
          currentX,
          y,
          char: grapheme,
          style: effectiveStyle,
        );
        if (charWidth == 2 && currentX + 1 < width) {
          writeCell(
            currentX + 1,
            y,
            char: '\u200B',
            style: effectiveStyle,
          );
        }
      }
      currentX += charWidth;
    }
  }

  /// Clears only cells touched during this buffer's previous use.
  ///
  /// Because front/back buffers alternate, cells outside their recorded dirty
  /// spans are already blank. This avoids an O(width * height) clear on every
  /// frame while preserving correct removal of content.
  void clear() {
    for (var y = 0; y < height; y++) {
      if (!isRowDirty(y)) continue;
      final start = _dirtyStart[y];
      final end = _dirtyEnd[y];
      for (var x = start; x <= end; x++) {
        _flatCells[_index(x, y)].reset();
      }
      _dirtyStart[y] = width;
      _dirtyEnd[y] = -1;
    }
    pendingImages.clear();
  }

  void fillArea(Rect area, String char, {TextStyle? style}) {
    final effectiveStyle = style ?? const TextStyle();
    final left = area.left.toInt().clamp(0, width);
    final top = area.top.toInt().clamp(0, height);
    final right = area.right.ceil().clamp(0, width);
    final bottom = area.bottom.ceil().clamp(0, height);

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        writeCell(x, y, char: char, style: effectiveStyle);
      }
    }
  }

  void markImageRegion(
    int x,
    int y,
    int imageWidth,
    int imageHeight,
    String sixelData,
  ) {
    if (!contains(x, y)) return;

    final clampedWidth = (x + imageWidth > width) ? width - x : imageWidth;
    final clampedHeight = (y + imageHeight > height) ? height - y : imageHeight;
    if (clampedWidth <= 0 || clampedHeight <= 0) return;

    for (var cy = y; cy < y + clampedHeight; cy++) {
      for (var cx = x; cx < x + clampedWidth; cx++) {
        writeCell(
          cx,
          cy,
          char: ' ',
          isImagePlaceholder: true,
        );
      }
    }

    pendingImages.add(PendingImage(
      x: x,
      y: y,
      width: clampedWidth,
      height: clampedHeight,
      sixelData: sixelData,
    ));
  }

  void clearPendingImages() => pendingImages.clear();
}

class _CellRow extends ListBase<Cell> {
  _CellRow(this.buffer, this.y);

  final Buffer buffer;
  final int y;

  @override
  int get length => buffer.width;

  @override
  set length(int value) {
    throw UnsupportedError('Terminal buffer rows have a fixed length.');
  }

  @override
  Cell operator [](int index) => buffer.getCell(index, y);

  @override
  void operator []=(int index, Cell value) => buffer.setCell(index, y, value);
}
