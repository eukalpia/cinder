# Colors

Cinder exposes Flutter-style named colors while retaining terminal-aware color
encoding and alpha compositing.

## Named colors

Use `Colors` for the complete palette:

```dart
const Text(
  'Connected',
  style: TextStyle(color: Colors.green),
);

const Container(
  color: Colors.deepPurple,
  child: Text('Command palette'),
);
```

For convenient non-conflicting names, `Color` also exposes direct constants:

```dart
const TextStyle(color: Color.white);
const Container(color: Color.black);
const Color overlay = Color.transparent;
```

`Color` already uses `red`, `green`, and `blue` as channel accessors. Therefore
those three named colors remain `Colors.red`, `Colors.green`, and `Colors.blue`,
matching Flutter's public palette pattern.

The extended palette includes `pink`, `purple`, `deepPurple`, `indigo`,
`lightBlue`, `cyan`, `teal`, `lightGreen`, `lime`, `amber`, `orange`,
`deepOrange`, `brown`, `grey`/`gray`, and `blueGrey`/`blueGray`.

## Integer construction

Six-digit values are interpreted as `0xRRGGBB` and remain fully opaque:

```dart
const Color red = Color(0xFF0000);
```

Eight-digit values use Flutter-compatible `0xAARRGGBB` ordering:

```dart
const Color halfRed = Color(0x80FF0000);
```

Other constructors and helpers:

```dart
const Color rgb = Color.fromRGB(139, 179, 244);
const Color argb = Color.fromARGB(128, 139, 179, 244);
final Color rgbo = Color.fromRGBO(139, 179, 244, 0.5);
final int packed = rgbo.toARGB32();
```
