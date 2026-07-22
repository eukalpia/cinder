import 'dart:async';
import 'dart:io';

import 'image_cleanup.dart';

/// Graphics, color, input, and control capabilities for a terminal session.
class TerminalCapabilities {
  TerminalCapabilities({
    this.supportsKittyGraphics = false,
    this.supportsITerm2Images = false,
    this.supportsSixel = false,
    this.supportsTrueColor = false,
    this.supports256Colors = false,
    this.supportsMouse = false,
    this.supportsBracketedPaste = false,
    this.supportsFocusEvents = false,
    this.supportsKittyKeyboard = false,
    this.supportsHyperlinks = false,
    this.supportsOsc52Clipboard = false,
    this.supportsSynchronizedOutput = false,
    this.isTmux = false,
    this.isSsh = false,
    this.isDumb = false,
    this.termType,
    this.termProgram,
    this.imageProtocolOverride,
  });

  bool supportsKittyGraphics;
  bool supportsITerm2Images;
  bool supportsSixel;
  bool supportsTrueColor;
  bool supports256Colors;
  bool supportsMouse;
  bool supportsBracketedPaste;
  bool supportsFocusEvents;
  bool supportsKittyKeyboard;
  bool supportsHyperlinks;
  bool supportsOsc52Clipboard;
  bool supportsSynchronizedOutput;
  bool isTmux;
  bool isSsh;
  bool isDumb;
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
    final term = environment['TERM']?.trim().toLowerCase() ?? '';
    final termProgram =
        environment['TERM_PROGRAM']?.trim().toLowerCase() ?? '';
    final colorterm = environment['COLORTERM']?.trim().toLowerCase() ?? '';
    final override =
        _parseProtocolOverride(environment['CINDER_IMAGE_PROTOCOL']);

    final isDumb = term == 'dumb';
    final isTmux = environment.containsKey('TMUX');
    final isSsh = environment.containsKey('SSH_CONNECTION') ||
        environment.containsKey('SSH_CLIENT') ||
        environment.containsKey('SSH_TTY');
    final isWezTerm =
        term.contains('wezterm') || termProgram.contains('wezterm');
    final isKitty =
        term.contains('kitty') || environment.containsKey('KITTY_WINDOW_ID');
    final isGhostty =
        term.contains('ghostty') || termProgram.contains('ghostty');
    final isITerm = termProgram.contains('iterm') ||
        environment.containsKey('ITERM_SESSION_ID');
    final isWindowsTerminal = environment.containsKey('WT_SESSION');
    final isVte = environment.containsKey('VTE_VERSION');
    final isXtermLike = term.contains('xterm') ||
        term.contains('screen') ||
        term.contains('tmux') ||
        isVte;
    final isModern = !isDumb &&
        (term.isNotEmpty ||
            termProgram.isNotEmpty ||
            isWindowsTerminal ||
            isKitty ||
            isWezTerm ||
            isGhostty ||
            isITerm);

    final trueColor = !isDumb &&
        (term.contains('truecolor') ||
            term.contains('24bit') ||
            colorterm == 'truecolor' ||
            colorterm == '24bit' ||
            isKitty ||
            isWezTerm ||
            isGhostty ||
            isITerm ||
            isWindowsTerminal);

    return TerminalCapabilities(
      supportsKittyGraphics: !isDumb &&
          (isKitty || isWezTerm || isGhostty) &&
          (!isTmux || environment.containsKey('KITTY_WINDOW_ID')),
      supportsITerm2Images: !isDumb && (isITerm || isWezTerm),
      supportsSixel: !isDumb && _isSixelTerm(environment, term),
      supportsTrueColor: trueColor,
      supports256Colors:
          trueColor || (!isDumb && term.contains('256color')),
      supportsMouse: isModern,
      supportsBracketedPaste: isModern,
      supportsFocusEvents: isModern &&
          (isXtermLike ||
              isKitty ||
              isWezTerm ||
              isGhostty ||
              isITerm ||
              isWindowsTerminal),
      supportsKittyKeyboard: !isDumb && (isKitty || isWezTerm || isGhostty),
      supportsHyperlinks: isModern &&
          (isXtermLike ||
              isKitty ||
              isWezTerm ||
              isGhostty ||
              isITerm ||
              isWindowsTerminal),
      supportsOsc52Clipboard: isModern &&
          (isXtermLike ||
              isKitty ||
              isWezTerm ||
              isGhostty ||
              isITerm ||
              isWindowsTerminal),
      supportsSynchronizedOutput: !isDumb &&
          (isKitty || isWezTerm || isGhostty || isITerm || isWindowsTerminal),
      isTmux: isTmux,
      isSsh: isSsh,
      isDumb: isDumb,
      termType: environment['TERM'],
      termProgram: environment['TERM_PROGRAM'],
      imageProtocolOverride: override,
    );
  }

  /// Detects environment capabilities and upgrades them with a DA1 response.
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
      // Environment detection remains the safe fallback.
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

  static bool _isSixelTerm(Map<String, String> environment, String term) {
    final explicit = environment['CINDER_SIXEL']?.trim().toLowerCase();
    if (explicit == '1' || explicit == 'true' || explicit == 'yes') return true;
    if (explicit == '0' || explicit == 'false' || explicit == 'no') return false;

    final features = environment['TERM_FEATURES']?.toLowerCase() ?? '';
    if (features.split(RegExp(r'[,;\s]+')).contains('sixel')) return true;

    const knownSixelTerms = <String>[
      'sixel',
      'mlterm',
      'yaft',
      'contour',
      'mintty',
    ];
    return knownSixelTerms.any(term.contains);
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
    bool? supportsMouse,
    bool? supportsBracketedPaste,
    bool? supportsFocusEvents,
    bool? supportsKittyKeyboard,
    bool? supportsHyperlinks,
    bool? supportsOsc52Clipboard,
    bool? supportsSynchronizedOutput,
    bool? isTmux,
    bool? isSsh,
    bool? isDumb,
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
      supportsMouse: supportsMouse ?? this.supportsMouse,
      supportsBracketedPaste:
          supportsBracketedPaste ?? this.supportsBracketedPaste,
      supportsFocusEvents: supportsFocusEvents ?? this.supportsFocusEvents,
      supportsKittyKeyboard:
          supportsKittyKeyboard ?? this.supportsKittyKeyboard,
      supportsHyperlinks: supportsHyperlinks ?? this.supportsHyperlinks,
      supportsOsc52Clipboard:
          supportsOsc52Clipboard ?? this.supportsOsc52Clipboard,
      supportsSynchronizedOutput:
          supportsSynchronizedOutput ?? this.supportsSynchronizedOutput,
      isTmux: isTmux ?? this.isTmux,
      isSsh: isSsh ?? this.isSsh,
      isDumb: isDumb ?? this.isDumb,
      termType: termType ?? this.termType,
      termProgram: termProgram ?? this.termProgram,
      imageProtocolOverride:
          imageProtocolOverride ?? this.imageProtocolOverride,
    );
  }

  @override
  String toString() {
    return 'TerminalCapabilities('
        'kittyGraphics: $supportsKittyGraphics, '
        'iterm2Images: $supportsITerm2Images, '
        'sixel: $supportsSixel, '
        'trueColor: $supportsTrueColor, '
        'colors256: $supports256Colors, '
        'mouse: $supportsMouse, '
        'bracketedPaste: $supportsBracketedPaste, '
        'focusEvents: $supportsFocusEvents, '
        'kittyKeyboard: $supportsKittyKeyboard, '
        'hyperlinks: $supportsHyperlinks, '
        'osc52Clipboard: $supportsOsc52Clipboard, '
        'synchronizedOutput: $supportsSynchronizedOutput, '
        'tmux: $isTmux, ssh: $isSsh, dumb: $isDumb, '
        'preferredImageProtocol: $preferredImageProtocol, '
        'termType: $termType, termProgram: $termProgram)';
  }
}
