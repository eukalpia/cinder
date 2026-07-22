# Icons in Cinder

Cinder exposes a Flutter-style icon layer while remaining a pure Dart terminal
framework.

## Packages

```yaml
dependencies:
  cinder:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
  cinder_material_icons:
    git:
      url: https://github.com/eukalpia/cinder.git
      path: packages/cinder_material_icons
      ref: main
  cinder_lucide:
    git:
      url: https://github.com/eukalpia/cinder.git
      path: packages/cinder_lucide
      ref: main
```

## API

```dart
const Icon(Icons.home);
const Icon(LucideIcons.activity);

IconTheme(
  data: const IconThemeData(
    color: Colors.cyan,
    renderMode: IconRenderMode.unicode,
  ),
  child: const Icon(Icons.settings),
);

IconButton(
  icon: const Icon(LucideIcons.x),
  tooltip: 'Close',
  onPressed: closePanel,
);
```

Core types are `IconData`, `Icon`, `IconThemeData`, `IconTheme`, `IconButton`,
and `TerminalIcons`.

## Rendering modes

| Mode | Behavior |
| --- | --- |
| `auto` | Real icon-font glyph when explicitly enabled, otherwise monochrome Unicode text |
| `unicode` | Terminal-safe Unicode text presentation; emoji selectors are removed |
| `emoji` | Preserve the Unicode fallback exactly, including emoji presentation |
| `ascii` | ASCII-only fallback |
| `font` | Original icon-font private-use code point |

The default no longer renders emoji-capable symbols as colorful emoji. Cinder
normalizes Unicode fallbacks to text presentation (`VS15`) so icons stay
monochrome and align with surrounding terminal text.

To use the original Material or Lucide icon-font glyphs, configure a terminal
font containing the corresponding private-use code points and opt in:

```dart
IconTheme(
  data: const IconThemeData(
    renderMode: IconRenderMode.auto,
    usePrivateUseGlyphs: true,
  ),
  child: const Icon(LucideIcons.settings),
);
```

`auto` then prefers the actual icon-font code point. Without that explicit
opt-in, Unicode text and ASCII remain the portable fallbacks. Cinder cannot
select a different font family for one terminal cell.

## Complete generated catalogs

`tool/generate_icon_packs.py` reads Flutter's stable Material icon declarations
and the official Lucide SVG tree. It generates pure Dart catalogs and preserves
Flutter/Lucide identifier naming. CI rejects unexpectedly small catalogs and
runs analyzer and package tests after generation.

## Width and RTL

Cinder measures the final grapheme with its Unicode width engine. Directional
fallbacks such as arrows and chevrons are mirrored when `matchTextDirection` is
set and the icon is rendered with `TextDirection.rtl`.
