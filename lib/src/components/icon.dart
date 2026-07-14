import '../framework/framework.dart';
import '../style.dart';
import '../theme/tui_theme.dart';
import '../utils/unicode_width.dart';
import 'basic.dart';
import 'gesture_detector.dart';
import 'stack.dart' show Alignment, TextDirection;

/// Controls how an [IconData] is converted into terminal cells.
enum IconRenderMode {
  /// Prefer a terminal-safe Unicode fallback and use the icon-font code point
  /// only when [IconThemeData.usePrivateUseGlyphs] is enabled.
  auto,

  /// Render the original icon-font code point.
  ///
  /// This requires the active terminal font to contain the icon pack.
  font,

  /// Render the terminal-safe Unicode fallback.
  unicode,

  /// Render the ASCII fallback.
  ascii,
}

/// Describes a Flutter-style icon in a terminal-safe form.
///
/// Cinder keeps the original font code point for API compatibility, while also
/// carrying Unicode and ASCII fallbacks for terminals that do not have the
/// Material or Lucide icon fonts installed.
class IconData {
  const IconData(
    this.codePoint, {
    this.fontFamily,
    this.fontPackage,
    this.matchTextDirection = false,
    this.name,
    this.unicodeFallback,
    this.asciiFallback = '?',
  });

  const IconData.terminal(
    String glyph, {
    this.name,
    this.asciiFallback = '?',
    this.matchTextDirection = false,
  })  : codePoint = null,
        fontFamily = null,
        fontPackage = null,
        unicodeFallback = glyph;

  final int? codePoint;
  final String? fontFamily;
  final String? fontPackage;
  final bool matchTextDirection;
  final String? name;
  final String? unicodeFallback;
  final String asciiFallback;

  String resolveGlyph({
    required IconRenderMode mode,
    required bool usePrivateUseGlyphs,
    required String fallbackGlyph,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final unicode = _resolveDirection(unicodeFallback, textDirection);
    final fontGlyph =
        codePoint == null ? null : String.fromCharCode(codePoint!);

    switch (mode) {
      case IconRenderMode.font:
        return fontGlyph ?? unicode ?? asciiFallbackOr(fallbackGlyph);
      case IconRenderMode.unicode:
        return unicode ?? asciiFallbackOr(fallbackGlyph);
      case IconRenderMode.ascii:
        return asciiFallbackOr(fallbackGlyph);
      case IconRenderMode.auto:
        if (unicode != null && unicode.isNotEmpty) return unicode;
        if (usePrivateUseGlyphs && fontGlyph != null) return fontGlyph;
        return asciiFallbackOr(fallbackGlyph);
    }
  }

  String asciiFallbackOr(String fallbackGlyph) {
    return asciiFallback.isEmpty ? fallbackGlyph : asciiFallback;
  }

  String? _resolveDirection(String? glyph, TextDirection direction) {
    if (!matchTextDirection ||
        direction != TextDirection.rtl ||
        glyph == null) {
      return glyph;
    }
    return switch (glyph) {
      '←' => '→',
      '→' => '←',
      '⇐' => '⇒',
      '⇒' => '⇐',
      '◀' => '▶',
      '▶' => '◀',
      '‹' => '›',
      '›' => '‹',
      _ => glyph,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IconData &&
            codePoint == other.codePoint &&
            fontFamily == other.fontFamily &&
            fontPackage == other.fontPackage &&
            matchTextDirection == other.matchTextDirection &&
            name == other.name &&
            unicodeFallback == other.unicodeFallback &&
            asciiFallback == other.asciiFallback;
  }

  @override
  int get hashCode => Object.hash(
        codePoint,
        fontFamily,
        fontPackage,
        matchTextDirection,
        name,
        unicodeFallback,
        asciiFallback,
      );

  @override
  String toString() => 'IconData(${name ?? codePoint ?? unicodeFallback})';
}

/// Styling inherited by descendant [Icon] widgets.
class IconThemeData {
  const IconThemeData({
    this.color,
    this.size,
    this.renderMode,
    this.usePrivateUseGlyphs,
    this.fallbackGlyph,
  });

  final Color? color;
  final double? size;
  final IconRenderMode? renderMode;
  final bool? usePrivateUseGlyphs;
  final String? fallbackGlyph;

  IconThemeData copyWith({
    Color? color,
    double? size,
    IconRenderMode? renderMode,
    bool? usePrivateUseGlyphs,
    String? fallbackGlyph,
  }) {
    return IconThemeData(
      color: color ?? this.color,
      size: size ?? this.size,
      renderMode: renderMode ?? this.renderMode,
      usePrivateUseGlyphs: usePrivateUseGlyphs ?? this.usePrivateUseGlyphs,
      fallbackGlyph: fallbackGlyph ?? this.fallbackGlyph,
    );
  }

  IconThemeData merge(IconThemeData? other) {
    if (other == null) return this;
    return IconThemeData(
      color: other.color ?? color,
      size: other.size ?? size,
      renderMode: other.renderMode ?? renderMode,
      usePrivateUseGlyphs: other.usePrivateUseGlyphs ?? usePrivateUseGlyphs,
      fallbackGlyph: other.fallbackGlyph ?? fallbackGlyph,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is IconThemeData &&
            color == other.color &&
            size == other.size &&
            renderMode == other.renderMode &&
            usePrivateUseGlyphs == other.usePrivateUseGlyphs &&
            fallbackGlyph == other.fallbackGlyph;
  }

  @override
  int get hashCode => Object.hash(
        color,
        size,
        renderMode,
        usePrivateUseGlyphs,
        fallbackGlyph,
      );
}

/// Applies icon defaults to a subtree.
class IconTheme extends InheritedWidget {
  const IconTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final IconThemeData data;

  static IconThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<IconTheme>();
    final tuiTheme = TuiTheme.of(context);
    return const IconThemeData(
      size: 1,
      renderMode: IconRenderMode.auto,
      usePrivateUseGlyphs: false,
      fallbackGlyph: '?',
    ).copyWith(
      color: inherited?.data.color ?? tuiTheme.onSurface,
      size: inherited?.data.size,
      renderMode: inherited?.data.renderMode,
      usePrivateUseGlyphs: inherited?.data.usePrivateUseGlyphs,
      fallbackGlyph: inherited?.data.fallbackGlyph,
    );
  }

  static IconThemeData? maybeOf(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<IconTheme>();
    return (element?.widget as IconTheme?)?.data;
  }

  static Widget merge({
    Key? key,
    required IconThemeData data,
    required Widget child,
  }) {
    return _MergedIconTheme(key: key, data: data, child: child);
  }

  @override
  bool updateShouldNotify(IconTheme oldWidget) => data != oldWidget.data;
}

class _MergedIconTheme extends StatelessWidget {
  const _MergedIconTheme({super.key, required this.data, required this.child});

  final IconThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconTheme(data: IconTheme.of(context).merge(data), child: child);
  }
}

/// Displays an [IconData] using terminal-safe glyph selection.
class Icon extends StatelessWidget {
  const Icon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.renderMode,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final IconRenderMode? renderMode;

  @override
  Widget build(BuildContext context) {
    final inherited = IconTheme.of(context);
    final glyph = icon?.resolveGlyph(
          mode: renderMode ?? inherited.renderMode ?? IconRenderMode.auto,
          usePrivateUseGlyphs: inherited.usePrivateUseGlyphs ?? false,
          fallbackGlyph: inherited.fallbackGlyph ?? '?',
          textDirection: textDirection ?? TextDirection.ltr,
        ) ??
        '';

    final glyphWidth = UnicodeWidth.stringWidth(glyph);
    final requestedWidth = (size ?? inherited.size ?? 1).ceil().clamp(1, 1024);
    final width = glyphWidth > requestedWidth ? glyphWidth : requestedWidth;

    return SizedBox(
      width: width.toDouble(),
      height: 1,
      child: Align(
        alignment: Alignment.center,
        child: Text(
          glyph,
          softWrap: false,
          maxLines: 1,
          style: TextStyle(color: color ?? inherited.color),
        ),
      ),
    );
  }
}

/// A Flutter-style clickable icon widget for terminal applications.
class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconSize = 1,
    this.padding = EdgeInsets.zero,
    this.color,
    this.disabledColor,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final double iconSize;
  final EdgeInsets padding;
  final Color? color;
  final Color? disabledColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final themedIcon = IconTheme.merge(
      data: IconThemeData(
        size: iconSize,
        color: enabled ? color : disabledColor,
      ),
      child: icon,
    );

    return GestureDetector(
      onTap: onPressed,
      child: Padding(padding: padding, child: themedIcon),
    );
  }
}

/// Terminal-native icons that do not require an icon font.
abstract final class TerminalIcons {
  static const IconData home =
      IconData.terminal('⌂', name: 'home', asciiFallback: 'H');
  static const IconData search =
      IconData.terminal('⌕', name: 'search', asciiFallback: '?');
  static const IconData menu =
      IconData.terminal('☰', name: 'menu', asciiFallback: '=');
  static const IconData close =
      IconData.terminal('×', name: 'close', asciiFallback: 'x');
  static const IconData check =
      IconData.terminal('✓', name: 'check', asciiFallback: 'v');
  static const IconData add =
      IconData.terminal('+', name: 'add', asciiFallback: '+');
  static const IconData remove =
      IconData.terminal('−', name: 'remove', asciiFallback: '-');
  static const IconData arrowLeft = IconData.terminal('←',
      name: 'arrowLeft', asciiFallback: '<', matchTextDirection: true);
  static const IconData arrowRight = IconData.terminal('→',
      name: 'arrowRight', asciiFallback: '>', matchTextDirection: true);
  static const IconData arrowUp =
      IconData.terminal('↑', name: 'arrowUp', asciiFallback: '^');
  static const IconData arrowDown =
      IconData.terminal('↓', name: 'arrowDown', asciiFallback: 'v');
  static const IconData warning =
      IconData.terminal('⚠', name: 'warning', asciiFallback: '!');
  static const IconData info =
      IconData.terminal('ⓘ', name: 'info', asciiFallback: 'i');
  static const IconData star =
      IconData.terminal('★', name: 'star', asciiFallback: '*');
  static const IconData heart =
      IconData.terminal('♥', name: 'heart', asciiFallback: '<3');
  static const IconData play =
      IconData.terminal('▶', name: 'play', asciiFallback: '>');
  static const IconData pause =
      IconData.terminal('Ⅱ', name: 'pause', asciiFallback: '||');
  static const IconData stop =
      IconData.terminal('■', name: 'stop', asciiFallback: '#');
}
