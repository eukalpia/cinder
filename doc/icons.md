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
| `auto` | Unicode fallback first, optionally private-use glyphs |
| `unicode` | Terminal-safe Unicode representation |
| `ascii` | ASCII-only fallback |
| `font` | Original icon-font code point |

Font mode only works when the user's terminal font contains the corresponding
Material or Lucide glyphs. Cinder does not and cannot change the terminal font
for an individual cell. Unicode and ASCII modes therefore remain the reliable
portable defaults.

## Complete generated catalogs

`tool/generate_icon_packs.py` reads Flutter's stable Material icon declarations
and the official Lucide SVG tree. It generates pure Dart catalogs and preserves
Flutter/Lucide identifier naming. CI rejects unexpectedly small catalogs and
runs analyzer and package tests after generation.

## Width and RTL

Cinder measures the final grapheme with its Unicode width engine. Directional
fallbacks such as arrows and chevrons are mirrored when `matchTextDirection` is
set and the icon is rendered with `TextDirection.rtl`.
