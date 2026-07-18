# Media playback

Cinder media playback uses FFprobe for metadata, FFmpeg for bounded RGBA video frames, and FFplay for audio output.

## Requirements

Install `ffmpeg`, `ffprobe`, and `ffplay`, then ensure all three commands are available on `PATH`.

Cinder passes `-nostdin` only to FFmpeg. FFplay does not support that option, including current Windows builds from gyan.dev.

## Complete player

`MediaPlayer` combines the direct video surface, seek bar, playback buttons, volume, mute, speed selection, viewport modes, keyboard shortcuts, and runtime status:

```dart
Expanded(
  child: MediaPlayer(
    controller: controller,
    title: 'movie.mp4',
    fit: MediaPlayerFit.contain,
  ),
)
```

The direct video surface updates an existing render object instead of sending every frame through the asynchronous static-image loader.

### Keyboard shortcuts

| Key | Action |
|---|---|
| Space or K | Play or pause |
| Left / Right | Seek 5 seconds |
| Shift + Left / Right | Seek 30 seconds |
| J / L | Seek backward or forward |
| Up / Down | Change volume |
| M | Mute or restore volume |
| [ / ] | Decrease or increase playback speed |
| 0–9 | Jump to 0–90 percent |
| Home / End | Beginning or end |
| F | Toggle contain/fullscreen cover |
| C | Show or hide controls |
| Q | Quit cleanly |

The seek bar and control buttons also support mouse input.

## Basic controller usage

```dart
final controller = MediaController(
  backend: FfmpegMediaBackend(
    maxVideoWidth: 240,
    maxVideoHeight: 135,
    maxFrameRate: 30,
  ),
);

await controller.open('movie.mp4', autoPlay: true);
```

## Responsive terminal layout

`MediaPlayer` and `VideoPlayer` rebuild against the actual parent constraints after terminal resize. `MediaPlayerFit.contain` preserves the complete source with letterboxing. `MediaPlayerFit.cover` fills the complete viewport and crops around the center. `MediaPlayerFit.fill` stretches to the complete viewport.

Leave explicit width and height unset and give the player the remaining space with `Expanded`.

Use `maxFrameRate: 60` only when the selected terminal protocol and machine can sustain it. The default 30 FPS limit keeps Unicode fallback rendering responsive on ordinary terminals.

Use `shutdownApp()` or `Ctrl+C` for a clean application exit. The media backend receives the shutdown signal and terminates its FFmpeg and FFplay children before the process ends.

Run `dart pub get` before formatting examples so the formatter uses the package language version.

## Runtime behavior

- Video is decoded to a bounded resolution before entering the Dart process.
- Frames are paced by presentation time instead of being emitted as quickly as FFmpeg can decode them.
- Late frames are discarded before they overload the widget tree.
- Equal-sized RGBA frame updates request repaint without relaying out the render tree.
- FFmpeg stderr is consumed and decoder failures are forwarded through the media stream.
- Media opening is atomic: a stale FFprobe completion cannot start playback after the controller was closed or disposed.
- `pause`, `seek`, and controller disposal terminate owned media processes.
- On Windows, Cinder terminates the complete FFmpeg or FFplay process tree with `taskkill /T /F`.
- SIGINT, SIGTERM, and SIGHUP cleanup hooks stop child processes when the host terminal exits.

## Emergency cleanup on Windows

Older builds could leave an FFplay process running after the TUI closed. Stop those stale processes once with:

```powershell
Get-Process ffplay,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force
```

Current builds clean up their own child processes automatically.
