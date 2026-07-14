import '../framework/framework.dart';
import '../style.dart';
import 'basic.dart';

/// Describes an icon glyph independently from a concrete terminal font.
///
/// [codePoint] and [fontFamily] preserve Flutter-style icon metadata for
/// terminals configured with a compatible icon font. [terminalGlyph] and
/// [asciiFallback] make the same icon usable on ordinary terminals.
class IconData {
  const IconData(
    this.codePoint, {
    this.fontFamily,
    this.fontPackage,
    this.matchTextDirection = false,
    this.terminalGlyph,
    this.asciiFallback = '?',
    this.semanticLabel,
  });

  final int codePoint;
  final String? fontFamily;
  final String? fontPackage;
  final bool matchTextDirection;
  final String? terminalGlyph;
  final String asciiFallback;
  final String? semanticLabel;

  String resolveGlyph({bool supportsIconFont = false}) {
    if (supportsIconFont && codePoint > 0) {
      return String.fromCharCode(codePoint);
    }
    return terminalGlyph ?? asciiFallback;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IconData &&
            other.codePoint == codePoint &&
            other.fontFamily == fontFamily &&
            other.fontPackage == fontPackage &&
            other.matchTextDirection == matchTextDirection &&
            other.terminalGlyph == terminalGlyph &&
            other.asciiFallback == asciiFallback &&
            other.semanticLabel == semanticLabel;
  }

  @override
  int get hashCode => Object.hash(
        codePoint,
        fontFamily,
        fontPackage,
        matchTextDirection,
        terminalGlyph,
        asciiFallback,
        semanticLabel,
      );
}

/// Styling inherited by descendant [Icon] widgets.
class IconThemeData {
  const IconThemeData({
    this.color,
    this.size = 1,
    this.supportsIconFont = false,
    this.fallbackGlyph,
  });

  final Color? color;

  /// Desired icon height in terminal cells.
  ///
  /// Single-cell font glyphs remain one terminal row. Vector icon adapters may
  /// use this value to rasterize larger icons.
  final int size;
  final bool supportsIconFont;
  final String? fallbackGlyph;

  IconThemeData copyWith({
    Color? color,
    int? size,
    bool? supportsIconFont,
    String? fallbackGlyph,
  }) {
    return IconThemeData(
      color: color ?? this.color,
      size: size ?? this.size,
      supportsIconFont: supportsIconFont ?? this.supportsIconFont,
      fallbackGlyph: fallbackGlyph ?? this.fallbackGlyph,
    );
  }

  IconThemeData merge(IconThemeData? other) {
    if (other == null) return this;
    return IconThemeData(
      color: other.color ?? color,
      size: other.size,
      supportsIconFont: other.supportsIconFont,
      fallbackGlyph: other.fallbackGlyph ?? fallbackGlyph,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IconThemeData &&
            other.color == color &&
            other.size == size &&
            other.supportsIconFont == supportsIconFont &&
            other.fallbackGlyph == fallbackGlyph;
  }

  @override
  int get hashCode => Object.hash(
        color,
        size,
        supportsIconFont,
        fallbackGlyph,
      );
}

/// Applies default icon styling to a subtree.
class IconTheme extends InheritedWidget {
  const IconTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final IconThemeData data;

  static IconThemeData of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data ??
        const IconThemeData();
  }

  static IconThemeData? maybeOf(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<IconTheme>();
    return (element?.widget as IconTheme?)?.data;
  }

  @override
  bool updateShouldNotify(IconTheme oldWidget) => data != oldWidget.data;
}

/// Displays an icon using Flutter-style [IconData] metadata.
class Icon extends StatelessWidget {
  const Icon(
    this.icon, {
    super.key,
    this.color,
    this.size,
    this.semanticLabel,
    this.supportsIconFont,
    this.fallbackGlyph,
  });

  final IconData? icon;
  final Color? color;
  final int? size;
  final String? semanticLabel;
  final bool? supportsIconFont;
  final String? fallbackGlyph;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();

    final inherited = IconTheme.of(context);
    final useIconFont = supportsIconFont ?? inherited.supportsIconFont;
    final resolvedFallback = fallbackGlyph ?? inherited.fallbackGlyph;
    var glyph = icon!.resolveGlyph(supportsIconFont: useIconFont);
    if (glyph == icon!.asciiFallback && resolvedFallback != null) {
      glyph = resolvedFallback;
    }

    return Text(
      glyph,
      style: TextStyle(color: color ?? inherited.color),
      softWrap: false,
      maxLines: 1,
    );
  }
}
