# Media playback

Cinder media playback uses FFprobe for metadata, FFmpeg for bounded RGBA video frames, and FFplay for audio output.

## Requirements

Install `ffmpeg`, `ffprobe`, and `ffplay`, then ensure all three commands are available on `PATH`.

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

Render the current frame with:

```dart
VideoPlayer(
  controller: controller,
  width: 100,
  height: 30,
)
```

## Runtime behavior

- Video is decoded to a bounded resolution before entering the Dart process.
- Frames are paced by presentation time instead of being emitted as quickly as FFmpeg can decode them.
- Late frames are discarded before they overload the widget tree.
- FFmpeg stderr is consumed and decoder failures are forwarded through the media stream.
- `pause`, `seek`, and controller disposal terminate owned media processes.
- On Windows, Cinder terminates the complete FFmpeg or FFplay process tree with `taskkill /T /F`.
- SIGINT, SIGTERM, and SIGHUP cleanup hooks stop child processes when the host terminal exits.

## Emergency cleanup on Windows

Older builds could leave an FFplay process running after the TUI closed. Stop those stale processes once with:

```powershell
Get-Process ffplay,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force
```

Current builds clean up their own child processes automatically.
