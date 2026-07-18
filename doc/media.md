# Media playback

Cinder media playback uses FFprobe for metadata, FFmpeg for bounded RGBA video frames, and FFplay for audio output.

## Requirements

Install `ffmpeg`, `ffprobe`, and `ffplay`, then ensure all three commands are available on `PATH`.

Cinder passes `-nostdin` only to FFmpeg. FFplay does not support that option, including current Windows builds from gyan.dev.

## Basic usage

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

`VideoPlayer` is adaptive by default. Leave `width` and `height` unset and give it the remaining layout space with `Expanded`:

```dart
Column(
  children: [
    Text('movie.mp4'),
    const SizedBox(height: 1),
    Expanded(
      child: VideoPlayer(
        controller: controller,
        fit: BoxFit.contain,
      ),
    ),
    const SizedBox(height: 1),
    Text('00:10 / 01:42'),
  ],
)
```

The player rebuilds against the actual parent constraints after terminal resize and preserves the source aspect ratio while accounting for tall terminal cells.

When `adaptive` is enabled, `width` and `height` are optional maximums rather than rigid dimensions:

```dart
VideoPlayer(
  controller: controller,
  width: 160,
  height: 45,
)
```

Use `adaptive: false` only when an exact fixed cell size is required.

Use `maxFrameRate: 60` only when the selected terminal protocol and machine can sustain it. The default 30 FPS limit keeps Unicode fallback rendering responsive on ordinary terminals.

Use `shutdownApp()` or `Ctrl+C` for a clean application exit. The media backend receives the shutdown signal and terminates its FFmpeg and FFplay children before the process ends.

Run `dart pub get` before formatting examples so the formatter uses the package language version.

## Runtime behavior

- Video is decoded to a bounded resolution before entering the Dart process.
- Frames are paced by presentation time instead of being emitted as quickly as FFmpeg can decode them.
- Late frames are discarded before they overload the widget tree.
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
