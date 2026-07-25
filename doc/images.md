# Terminal image rendering

Cinder renders images as terminal-aware render objects rather than printing raw
escape sequences from application code.

## Sources

- `Image.file(path)`
- `Image.network(url)`
- `Image.memory(encodedBytes)`
- `Image.rgba(pixels, pixelWidth:, pixelHeight:)`
- custom `ImageProvider` implementations

PNG, JPEG, GIF, BMP, WebP, and other formats supported by `package:image` are
decoded to RGBA. Corrupt or unsupported input reaches `errorWidget` instead of
silently rendering invalid pixels.

## Protocol selection

| Protocol | Typical terminals | Cleanup |
| --- | --- | --- |
| Kitty graphics | Kitty, WezTerm, Ghostty | Native image ID deletion |
| iTerm2 inline images | iTerm2, WezTerm | Region overwrite |
| Sixel | xterm with Sixel, mlterm, mintty, foot, contour | Region overwrite |
| Unicode half blocks | Every color terminal | Ordinary cell diff |

Auto-detection uses `TERM`, `TERM_PROGRAM`, `KITTY_WINDOW_ID`,
`ITERM_SESSION_ID`, `COLORTERM`, and DA1 capability responses. Override it with:

```bash
CINDER_IMAGE_PROTOCOL=kitty dart run bin/app.dart
CINDER_IMAGE_PROTOCOL=iterm2 dart run bin/app.dart
CINDER_IMAGE_PROTOCOL=sixel dart run bin/app.dart
CINDER_IMAGE_PROTOCOL=unicode dart run bin/app.dart
```

## Renderer integration

Protocol images are tracked as overlays with position, dimensions, protocol,
encoded payload, and optional Kitty image ID. Their placeholder cells participate
in dirty-span comparison. Cached `RepaintBoundary` layers translate overlay
metadata during compositing, and active image regions prevent unsafe hardware
scroll-region acceleration.

Cinder emits an unchanged protocol image only once. Moving, replacing, or
unmounting it triggers protocol-appropriate cleanup and re-emission.

## Fallback behavior

Unicode half blocks encode two vertical pixels per terminal cell with foreground
and background true-color values. This mode is slower and lower-resolution than
native graphics, but it behaves correctly in redirected output, tests, VS Code,
GNOME Terminal, Windows Terminal, and other terminals without image protocols.

## Security

`Image.network` performs an ordinary HTTP(S) request. Applications that display
untrusted URLs should enforce their own allowed schemes, hosts, response size,
timeouts, and authentication policy before constructing the provider.
