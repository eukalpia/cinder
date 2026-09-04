# Cinder Flutter web host

This optional Flutter application hosts a compiled Cinder guest using the Dart
`xterm` widget and `WebBackend` bridge. The public documentation site uses its own
JavaScript xterm.js host under `docs-site/`.

The host and guest are separate builds. From this directory:

```bash
flutter pub get
cd example
dart pub get
dart compile js lib/main.dart -O2 -o ../web/app.js
cd ..
flutter run -d chrome
```

For a static export, run `flutter build web` after compiling the guest. Serve
`build/web/` over HTTP. For deployment under a subdirectory, pass its full path
with a trailing slash, for example `flutter build web --base-href /demo/`.

By default the host loads `app.js` relative to the page. The `?app=` query
parameter can select another compiled guest script. Only use guest scripts you
trust; they execute in the host page.

The host forwards terminal output, keyboard input, and resize events through
`WebBackend`, and requests guest shutdown when the widget is disposed.

Validate the wrapper with `flutter analyze` and `flutter build web`.
