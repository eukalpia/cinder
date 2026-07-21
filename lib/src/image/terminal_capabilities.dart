import 'dart:async';
import 'dart:io';

import 'image_cleanup.dart';

/// Graphics and color capabilities available in the current terminal session.
class TerminalCapabilities {
  TerminalCapabilities({
    this.supportsKittyGraphics = false,
    this.supportsITerm2Images = false,
    this.supportsSixel = false,
    this.supportsTrueColor = false,
    this.supports256Colors = false,
    this.termType,
    this.termProgram,
    this.imageProtocolOverride,
  });

  bool supportsKittyGraphics;
  bool supportsITerm2Images;
  bool supportsSixel;
  bool supportsTrueColor;
  bool supports256Colors;
  String? termType;
  String? termProgram;
  ImageProtocol? imageProtocolOverride;

  bool get supportsNativeImages =>
      supportsKittyGraphics || supportsITerm2Images || supportsSixel;

  ImageProtocol get preferredImageProtocol {
    final override = imageProtocolOverride;
    if (override != null) return override;
    if (supportsKittyGraphics) return ImageProtocol.kitty;
    if (supportsITerm2Images) return ImageProtocol.iterm2;
    if (supportsSixel) return ImageProtocol.sixel;
    return ImageProtocol.unicodeBlocks;
  }

  /// Performs deterministic environment-based capability detection.
  static TerminalCapabilities fromEnvironment(Map<String, String> environment) {
    final term = environment['TERM']?.toLowerCase() ?? '';
    final termProgram = environment['TERM_PROGRAM']?.toLowerCase() ?? '';
    final colorterm = environment['COLORTERM']?.toLowerCase() ?? '';
    final override =
        _parseProtocolOverride(environment['CINDER_IMAGE_PROTOCOL']);

    final isVSCode = termProgram.contains('vscode');
    final isWindowsTerminal = environment.containsKey('WT_SESSION') ||
        environment.containsKey('WT_PROFILE_ID') ||
        termProgram.contains('windows terminal') ||
        termProgram.contains('windows_terminal');
    final forcesTextFallback = isVSCode || isWindowsTerminal;

    final isWezTerm =
        term.contains('wezterm') || termProgram.contains('wezterm');
    final isKitty =
        term.contains('kitty') || environment.containsKey('KITTY_WINDOW_ID');
    final isGhostty =
        term.contains('ghostty') || termProgram.contains('ghostty');
    final isITerm = termProgram.contains('iterm') ||
        environment.containsKey('ITERM_SESSION_ID');

    return TerminalCapabilities(
      // VS Code and Windows Terminal frequently expose TERM=xterm-256color even
      // though they do not implement Kitty, iTerm2, or Sixel image protocols.
      // Treat them as text-only unless the user explicitly sets
      // CINDER_IMAGE_PROTOCOL.
      supportsKittyGraphics:
          !forcesTextFallback && (isKitty || isWezTerm || isGhostty),
      supportsITerm2Images: !forcesTextFallback && (isITerm || isWezTerm),
      supportsSixel:
          !forcesTextFallback && _isSixelTermByName(term, termProgram),
      supportsTrueColor: term.contains('truecolor') ||
          term.contains('24bit') ||
          colorterm == 'truecolor' ||
          colorterm == '24bit',
      supports256Colors: term.contains('256color') ||
          term.contains('truecolor') ||
          term.contains('24bit'),
      termType: environment['TERM'],
      termProgram: environment['TERM_PROGRAM'],
      imageProtocolOverride: override,
    );
  }

  /// Detects environment capabilities and upgrades them with DA1 responses.
  static Future<TerminalCapabilities> detect({
    Duration timeout = const Duration(milliseconds: 100),
    Stream<List<int>>? stdinStream,
    IOSink? stdoutSink,
    Map<String, String>? environment,
  }) async {
    final capabilities = fromEnvironment(environment ?? Platform.environment);
    try {
      final detected = await _queryDA1(
        timeout: timeout,
        stdinStream: stdinStream,
        stdoutSink: stdoutSink,
      );
      if (detected != null) {
        capabilities.supportsSixel |= detected.supportsSixel;
        capabilities.supports256Colors |= detected.supports256Colors;
      }
    } catch (_) {
      // Environment detection remains a safe fallback.
    }
    return capabilities;
  }

  static ImageProtocol? _parseProtocolOverride(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'kitty' => ImageProtocol.kitty,
      'iterm' || 'iterm2' => ImageProtocol.iterm2,
      'sixel' => ImageProtocol.sixel,
      'unicode' || 'blocks' || 'unicodeblocks' => ImageProtocol.unicodeBlocks,
      _ => null,
    };
  }

  static bool _isSixelTermByName(String term, String termProgram) {
    // Generic xterm-256color is intentionally not considered proof of Sixel
    // support. VS Code, Windows Terminal, tmux, SSH sessions, and many other
    // terminals use that value without implementing Sixel.
    const sixelTerms = <String>[
      'xterm-sixel',
      'mlterm',
      'yaft',
      'foot',
      'contour',
      'wezterm',
      'mintty',
      'sixel',
    ];
    return sixelTerms.any(term.contains) ||
        sixelTerms.any(termProgram.contains);
  }

  static Future<TerminalCapabilities?> _queryDA1({
    required Duration timeout,
    Stream<List<int>>? stdinStream,
    IOSink? stdoutSink,
  }) async {
    final effectiveStdin = stdinStream ?? _getRawStdin();
    final IOSink? effectiveStdout =
        stdoutSink ?? (Platform.isWindows ? null : stdout);
    if (effectiveStdin == null || effectiveStdout == null) return null;

    effectiveStdout.write('\x1b[c');
    await effectiveStdout.flush();

    final completer = Completer<String>();
    final buffer = StringBuffer();
    late StreamSubscription<List<int>> subscription;
    subscription = effectiveStdin.listen(
      (data) {
        buffer.write(String.fromCharCodes(data));
        final response = buffer.toString();
        if (response.contains('c')) {
          subscription.cancel();
          if (!completer.isCompleted) completer.complete(response);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
    );

    try {
      return _parseDA1Response(await completer.future.timeout(timeout));
    } on TimeoutException {
      await subscription.cancel();
      return null;
    } catch (_) {
      await subscription.cancel();
      return null;
    }
  }

  static Stream<List<int>>? _getRawStdin() {
    try {
      return stdin.hasTerminal ? stdin : null;
    } catch (_) {
      return null;
    }
  }

  static TerminalCapabilities? _parseDA1Response(String response) {
    final match = RegExp(r'\x1b\[\?([0-9;]+)c').firstMatch(response);
    if (match == null) return null;

    final capabilities = TerminalCapabilities();
    for (final parameter in match.group(1)!.split(';').map(int.tryParse)) {
      if (parameter == 4) capabilities.supportsSixel = true;
      if (parameter == 22) capabilities.supports256Colors = true;
    }
    return capabilities;
  }

  TerminalCapabilities copyWith({
    bool? supportsKittyGraphics,
    bool? supportsITerm2Images,
    bool? supportsSixel,
    bool? supportsTrueColor,
    bool? supports256Colors,
    String? termType,
    String? termProgram,
    ImageProtocol? imageProtocolOverride,
  }) {
    return TerminalCapabilities(
      supportsKittyGraphics:
          supportsKittyGraphics ?? this.supportsKittyGraphics,
      supportsITerm2Images: supportsITerm2Images ?? this.supportsITerm2Images,
      supportsSixel: supportsSixel ?? this.supportsSixel,
      supportsTrueColor: supportsTrueColor ?? this.supportsTrueColor,
      supports256Colors: supports256Colors ?? this.supports256Colors,
      termType: termType ?? this.termType,
      termProgram: termProgram ?? this.termProgram,
      imageProtocolOverride:
          imageProtocolOverride ?? this.imageProtocolOverride,
    );
  }

  @override
  String toString() {
    return 'TerminalCapabilities('
        'kitty: $supportsKittyGraphics, '
        'iterm2: $supportsITerm2Images, '
        'sixel: $supportsSixel, '
        'trueColor: $supportsTrueColor, '
        'colors256: $supports256Colors, '
        'preferredImageProtocol: $preferredImageProtocol, '
        'termType: $termType, '
        'termProgram: $termProgram)';
  }
}
