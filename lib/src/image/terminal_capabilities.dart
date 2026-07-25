import 'dart:async';
import 'dart:io';

import 'image_cleanup.dart';

/// Immutable graphics, color, input, and control capabilities for one session.
///
/// Environment detection is intentionally conservative. Interactive terminal
/// control is disabled for CI, dumb terminals, and redirected input/output.
/// Active probing is opt-in because reading terminal responses competes with an
/// application's normal input stream.
final class TerminalCapabilities {
  const TerminalCapabilities({
    this.supportsKittyGraphics = false,
    this.supportsITerm2Images = false,
    this.supportsSixel = false,
    this.supportsTrueColor = false,
    this.supports256Colors = false,
    this.supportsMouse = false,
    this.supportsBracketedPaste = false,
    this.supportsFocusEvents = false,
    this.supportsKittyKeyboard = false,
    this.supportsModifyOtherKeys = false,
    this.supportsHyperlinks = false,
    this.supportsOsc52Clipboard = false,
    this.supportsSynchronizedOutput = false,
    this.supportsRawMode = false,
    this.supportsAlternateScreen = false,
    this.isInteractive = false,
    this.isTmux = false,
    this.isScreen = false,
    this.isSsh = false,
    this.isCi = false,
    this.isRedirected = false,
    this.isDumb = false,
    this.termType,
    this.termProgram,
    this.imageProtocolOverride,
  });

  final bool supportsKittyGraphics;
  final bool supportsITerm2Images;
  final bool supportsSixel;
  final bool supportsTrueColor;
  final bool supports256Colors;
  final bool supportsMouse;
  final bool supportsBracketedPaste;
  final bool supportsFocusEvents;
  final bool supportsKittyKeyboard;
  final bool supportsModifyOtherKeys;
  final bool supportsHyperlinks;
  final bool supportsOsc52Clipboard;
  final bool supportsSynchronizedOutput;
  final bool supportsRawMode;
  final bool supportsAlternateScreen;
  final bool isInteractive;
  final bool isTmux;
  final bool isScreen;
  final bool isSsh;
  final bool isCi;
  final bool isRedirected;
  final bool isDumb;
  final String? termType;
  final String? termProgram;
  final ImageProtocol? imageProtocolOverride;

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
  static TerminalCapabilities fromEnvironment(
    Map<String, String> environment, {
    bool stdinHasTerminal = true,
    bool stdoutHasTerminal = true,
  }) {
    final term = environment['TERM']?.trim().toLowerCase() ?? '';
    final termProgram = environment['TERM_PROGRAM']?.trim().toLowerCase() ?? '';
    final colorterm = environment['COLORTERM']?.trim().toLowerCase() ?? '';
    final override = _parseProtocolOverride(
      environment['CINDER_IMAGE_PROTOCOL'],
    );

    final isDumb = term == 'dumb';
    final isCi = _truthy(environment['CI']) ||
        _truthy(environment['GITHUB_ACTIONS']) ||
        _truthy(environment['BUILDKITE']) ||
        _truthy(environment['GITLAB_CI']);
    final isRedirected = !stdinHasTerminal || !stdoutHasTerminal;
    final forceInteractive = _truthy(environment['CINDER_FORCE_INTERACTIVE']);
    final isInteractive =
        !isDumb && (forceInteractive || (!isCi && !isRedirected));
    final isTmux = environment.containsKey('TMUX');
    final isScreen = term.startsWith('screen');
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
    final isConPty = environment.containsKey('ConEmuPID') || isWindowsTerminal;
    final isVte = environment.containsKey('VTE_VERSION');
    final isXtermLike =
        term.contains('xterm') || isScreen || isTmux || isVte || isConPty;
    final isModern = isInteractive &&
        (term.isNotEmpty ||
            termProgram.isNotEmpty ||
            isWindowsTerminal ||
            isKitty ||
            isWezTerm ||
            isGhostty ||
            isITerm);

    final noColor = environment.containsKey('NO_COLOR') ||
        _truthy(environment['CINDER_NO_COLOR']);
    final trueColor = !noColor &&
        !isDumb &&
        (term.contains('truecolor') ||
            term.contains('24bit') ||
            colorterm == 'truecolor' ||
            colorterm == '24bit' ||
            isKitty ||
            isWezTerm ||
            isGhostty ||
            isITerm ||
            isWindowsTerminal);

    final tmuxKittyPassthrough =
        _truthy(environment['CINDER_TMUX_KITTY_PASSTHROUGH']);
    final nativeKittyGraphics = isKitty || isWezTerm || isGhostty;

    return TerminalCapabilities(
      supportsKittyGraphics: isInteractive &&
          nativeKittyGraphics &&
          (!isTmux ||
              tmuxKittyPassthrough ||
              environment.containsKey('KITTY_WINDOW_ID')),
      supportsITerm2Images: isInteractive && (isITerm || isWezTerm),
      supportsSixel: isInteractive && _isSixelTerm(environment, term),
      supportsTrueColor: trueColor,
      supports256Colors:
          !noColor && (trueColor || (!isDumb && term.contains('256color'))),
      supportsMouse: isModern,
      supportsBracketedPaste: isModern,
      supportsFocusEvents: isModern &&
          (isXtermLike ||
              isKitty ||
              isWezTerm ||
              isGhostty ||
              isITerm ||
              isWindowsTerminal),
      supportsKittyKeyboard:
          isInteractive && (isKitty || isWezTerm || isGhostty),
      supportsModifyOtherKeys: isInteractive &&
          !isKitty &&
          (isXtermLike || isITerm || isWindowsTerminal),
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
      supportsSynchronizedOutput: isInteractive &&
          (isKitty || isWezTerm || isGhostty || isITerm || isWindowsTerminal),
      supportsRawMode: isInteractive,
      supportsAlternateScreen: isInteractive,
      isInteractive: isInteractive,
      isTmux: isTmux,
      isScreen: isScreen,
      isSsh: isSsh,
      isCi: isCi,
      isRedirected: isRedirected,
      isDumb: isDumb,
      termType: environment['TERM'],
      termProgram: environment['TERM_PROGRAM'],
      imageProtocolOverride: override,
    );
  }

  /// Detects environment capabilities and optionally upgrades them with DA1.
  static Future<TerminalCapabilities> detect({
    Duration timeout = const Duration(milliseconds: 100),
    Stream<List<int>>? stdinStream,
    IOSink? stdoutSink,
    Map<String, String>? environment,
    bool activeQueries = false,
    bool? stdinHasTerminal,
    bool? stdoutHasTerminal,
  }) async {
    final effectiveStdinHasTerminal = stdinHasTerminal ?? _stdinHasTerminal();
    final effectiveStdoutHasTerminal =
        stdoutHasTerminal ?? _stdoutHasTerminal();
    var capabilities = fromEnvironment(
      environment ?? Platform.environment,
      stdinHasTerminal: effectiveStdinHasTerminal,
      stdoutHasTerminal: effectiveStdoutHasTerminal,
    );

    if (!activeQueries || !capabilities.isInteractive) return capabilities;

    try {
      final detected = await _queryDA1(
        timeout: timeout,
        stdinStream: stdinStream,
        stdoutSink: stdoutSink,
      );
      if (detected != null) {
        capabilities = capabilities.copyWith(
          supportsSixel: capabilities.supportsSixel || detected.supportsSixel,
          supports256Colors:
              capabilities.supports256Colors || detected.supports256Colors,
        );
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

  static bool _truthy(String? value) {
    return switch (value?.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      _ => false,
    };
  }

  static bool _isSixelTerm(Map<String, String> environment, String term) {
    final explicit = environment['CINDER_SIXEL']?.trim().toLowerCase();
    if (explicit == '1' || explicit == 'true' || explicit == 'yes') return true;
    if (explicit == '0' || explicit == 'false' || explicit == 'no') {
      return false;
    }

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
          unawaited(subscription.cancel());
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

  static bool _stdinHasTerminal() {
    try {
      return stdin.hasTerminal;
    } catch (_) {
      return false;
    }
  }

  static bool _stdoutHasTerminal() {
    try {
      return stdout.hasTerminal;
    } catch (_) {
      return false;
    }
  }

  static TerminalCapabilities? _parseDA1Response(String response) {
    final match = RegExp(r'\x1b\[\?([0-9;]+)c').firstMatch(response);
    if (match == null) return null;

    var supportsSixel = false;
    var supports256Colors = false;
    for (final parameter in match.group(1)!.split(';').map(int.tryParse)) {
      if (parameter == 4) supportsSixel = true;
      if (parameter == 22) supports256Colors = true;
    }
    return TerminalCapabilities(
      supportsSixel: supportsSixel,
      supports256Colors: supports256Colors,
    );
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
    bool? supportsModifyOtherKeys,
    bool? supportsHyperlinks,
    bool? supportsOsc52Clipboard,
    bool? supportsSynchronizedOutput,
    bool? supportsRawMode,
    bool? supportsAlternateScreen,
    bool? isInteractive,
    bool? isTmux,
    bool? isScreen,
    bool? isSsh,
    bool? isCi,
    bool? isRedirected,
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
      supportsModifyOtherKeys:
          supportsModifyOtherKeys ?? this.supportsModifyOtherKeys,
      supportsHyperlinks: supportsHyperlinks ?? this.supportsHyperlinks,
      supportsOsc52Clipboard:
          supportsOsc52Clipboard ?? this.supportsOsc52Clipboard,
      supportsSynchronizedOutput:
          supportsSynchronizedOutput ?? this.supportsSynchronizedOutput,
      supportsRawMode: supportsRawMode ?? this.supportsRawMode,
      supportsAlternateScreen:
          supportsAlternateScreen ?? this.supportsAlternateScreen,
      isInteractive: isInteractive ?? this.isInteractive,
      isTmux: isTmux ?? this.isTmux,
      isScreen: isScreen ?? this.isScreen,
      isSsh: isSsh ?? this.isSsh,
      isCi: isCi ?? this.isCi,
      isRedirected: isRedirected ?? this.isRedirected,
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
        'interactive: $isInteractive, rawMode: $supportsRawMode, '
        'alternateScreen: $supportsAlternateScreen, '
        'kittyGraphics: $supportsKittyGraphics, '
        'iterm2Images: $supportsITerm2Images, sixel: $supportsSixel, '
        'trueColor: $supportsTrueColor, colors256: $supports256Colors, '
        'mouse: $supportsMouse, bracketedPaste: $supportsBracketedPaste, '
        'focusEvents: $supportsFocusEvents, '
        'kittyKeyboard: $supportsKittyKeyboard, '
        'modifyOtherKeys: $supportsModifyOtherKeys, '
        'hyperlinks: $supportsHyperlinks, '
        'osc52Clipboard: $supportsOsc52Clipboard, '
        'synchronizedOutput: $supportsSynchronizedOutput, '
        'tmux: $isTmux, screen: $isScreen, ssh: $isSsh, ci: $isCi, '
        'redirected: $isRedirected, dumb: $isDumb, '
        'preferredImageProtocol: $preferredImageProtocol, '
        'termType: $termType, termProgram: $termProgram)';
  }
}
