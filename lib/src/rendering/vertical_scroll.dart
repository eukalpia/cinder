part of '../binding/terminal_binding.dart';

int _detectVerticalShift(buf.Buffer current, buf.Buffer previous) {
  final width = current.width;
  final height = current.height;
  if (width != previous.width ||
      height != previous.height ||
      width == 0 ||
      height < 2 ||
      current.pendingImages.isNotEmpty ||
      previous.pendingImages.isNotEmpty) {
    return 0;
  }

  bool rowsMatch(int currentY, int previousY) {
    for (var x = 0; x < width; x++) {
      if (!current
          .getCell(x, currentY)
          .matches(previous.getCell(x, previousY))) {
        return false;
      }
    }
    return true;
  }

  // Unchanged headers and ordinary sparse updates do not need a shift search.
  if (rowsMatch(0, 0)) return 0;

  bool matchesShift(int shift) {
    final currentStart = shift > 0 ? 0 : -shift;
    final previousStart = shift > 0 ? shift : 0;
    final overlap = height - shift.abs();
    for (var y = 0; y < overlap; y++) {
      if (!rowsMatch(currentStart + y, previousStart + y)) return false;
    }
    // Images in exposed rows must also disqualify the hardware operation.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (current.getCell(x, y).isImagePlaceholder ||
            previous.getCell(x, y).isImagePlaceholder) {
          return false;
        }
      }
    }
    return true;
  }

  // Bound work for repeated rows while covering common wheel/key scrolls.
  // Larger jumps continue through the ordinary differential renderer.
  final maximum = (height ~/ 2).clamp(0, 8);
  for (var amount = 1; amount <= maximum; amount++) {
    // Tiny overlaps cannot repay scroll-region and cursor escape overhead.
    if ((height - amount) * width < 32) break;
    if (rowsMatch(0, amount) && matchesShift(amount)) return amount;
    if (rowsMatch(amount, 0) && matchesShift(-amount)) return -amount;
  }
  return 0;
}
