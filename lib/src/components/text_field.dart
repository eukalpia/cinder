import 'dart:async';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:cinder/cinder.dart' hide TextAlign;
import 'package:cinder/src/framework/terminal_canvas.dart';
import '../rendering/mouse_hit_test.dart';
import '../rendering/mouse_tracker.dart';
import '../text/text_layout_engine.dart';
import '../utils/unicode_width.dart';
import '../text/selection_utils.dart' as selection_utils;
import 'text_field/cursor_movement.dart';

/// A complete text editing value containing both text and selection.
class TextEditingValue {
  const TextEditingValue({required this.text, required this.selection});

  const TextEditingValue.empty()
      : text = '',
        selection = const TextSelection.collapsed(offset: 0);

  final String text;
  final TextSelection selection;

  TextEditingValue copyWith({String? text, TextSelection? selection}) {
    return TextEditingValue(
      text: text ?? this.text,
      selection: selection ?? this.selection,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TextEditingValue &&
            other.text == text &&
            other.selection == selection;
  }

  @override
  int get hashCode => Object.hash(text, selection);
}

/// Text selection representation.
class TextSelection {
  const TextSelection({required this.baseOffset, required this.extentOffset});

  const TextSelection.collapsed({required int offset})
      : baseOffset = offset,
        extentOffset = offset;

  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => math.min(baseOffset, extentOffset);
  int get end => math.max(baseOffset, extentOffset);

  TextSelection copyWith({int? baseOffset, int? extentOffset}) {
    return TextSelection(
      baseOffset: baseOffset ?? this.baseOffset,
      extentOffset: extentOffset ?? this.extentOffset,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextSelection &&
        other.baseOffset == baseOffset &&
        other.extentOffset == extentOffset;
  }

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);
}

/// Controls the text being edited and owns its undo/redo history.
class TextEditingController {
  TextEditingController({String? text, this.historyLimit = 100})
      : _value = TextEditingValue(
          text: text ?? '',
          selection: TextSelection.collapsed(offset: text?.length ?? 0),
        );

  TextEditingValue _value;
  final List<TextEditingValue> _undoStack = <TextEditingValue>[];
  final List<TextEditingValue> _redoStack = <TextEditingValue>[];
  final _listeners = <VoidCallback>[];

  /// Maximum number of text mutations retained for undo.
  final int historyLimit;

  TextEditingValue get value => _value;
  set value(TextEditingValue newValue) => setValue(newValue);

  /// The current text being edited.
  String get text => _value.text;
  set text(String newText) {
    setValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      ),
    );
  }

  /// The current selection.
  TextSelection get selection => _value.selection;
  set selection(TextSelection newSelection) {
    setValue(_value.copyWith(selection: newSelection), recordHistory: false);
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Atomically updates text and selection.
  ///
  /// Selection-only changes are never added to undo history. Text changes are
  /// recorded unless [recordHistory] is false (useful for restoring drafts).
  void setValue(TextEditingValue newValue, {bool recordHistory = true}) {
    final normalized = _normalize(newValue);
    if (normalized == _value) return;

    final textChanged = normalized.text != _value.text;
    if (recordHistory && textChanged && historyLimit > 0) {
      _undoStack.add(_value);
      if (_undoStack.length > historyLimit) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
    }

    _value = normalized;
    notifyListeners();
  }

  TextEditingValue _normalize(TextEditingValue candidate) {
    final length = candidate.text.length;
    return candidate.copyWith(
      selection: TextSelection(
        baseOffset: candidate.selection.baseOffset.clamp(0, length),
        extentOffset: candidate.selection.extentOffset.clamp(0, length),
      ),
    );
  }

  bool undo() {
    if (_undoStack.isEmpty) return false;
    final previous = _undoStack.removeLast();
    _redoStack.add(_value);
    _value = _normalize(previous);
    notifyListeners();
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) return false;
    final next = _redoStack.removeLast();
    _undoStack.add(_value);
    _value = _normalize(next);
    notifyListeners();
    return true;
  }

  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Clear the text.
  void clear() {
    value = const TextEditingValue.empty();
  }

  /// Add a listener.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners.
  void notifyListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Dispose of the controller.
  void dispose() {
    _listeners.clear();
    clearHistory();
  }
}

/// Persistence contract for per-conversation text drafts.
abstract class TextDraftStore {
  const TextDraftStore();

  TextEditingValue? read(Object key);
  void write(Object key, TextEditingValue value);
  void remove(Object key);
}

/// In-memory draft store suitable for chat tabs and workspace panes.
class MemoryTextDraftStore extends TextDraftStore {
  MemoryTextDraftStore();

  final Map<Object, TextEditingValue> _drafts = <Object, TextEditingValue>{};

  @override
  TextEditingValue? read(Object key) => _drafts[key];

  @override
  void write(Object key, TextEditingValue value) {
    _drafts[key] = value;
  }

  @override
  void remove(Object key) {
    _drafts.remove(key);
  }

  void clear() => _drafts.clear();
}

/// Determines which Enter chord submits a [TextField].
enum TextFieldSubmitMode {
  /// Plain Enter submits. Shift+Enter inserts a newline in multiline fields.
  enter,

  /// Ctrl+Enter or Meta+Enter submits. Plain Enter inserts a newline.
  controlOrMetaEnter,

  /// Shift+Enter submits. Plain Enter inserts a newline.
  shiftEnter,

  /// Enter never submits and inserts a newline when multiline.
  never,
}

/// A Material Design text field for terminal UI.
class TextField extends StatefulWidget {
  const TextField({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.decoration,
    this.style,
    this.placeholder,
    this.placeholderStyle,
    this.textAlign = TextAlign.left,
    this.readOnly = false,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onPaste,
    this.onEditorKeyEvent,
    this.onAppKeyEvent,
    this.onKeyEvent,
    this.submitMode = TextFieldSubmitMode.enter,
    this.draftKey,
    this.draftStore,
    this.clearDraftOnSubmit = false,
    this.enabled = true,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.cursorBlinkRate,
    this.selectionColor,
    this.showCursor = true,
    this.width,
    this.height,
  })  : assert(maxLines == null || maxLines > 0),
        assert(minLines == null || minLines > 0),
        assert(
          (maxLines == null) || (minLines == null) || (maxLines >= minLines),
          "minLines can't be greater than maxLines",
        ),
        assert(
          !obscureText || maxLines == 1,
          'Obscured fields cannot be multiline.',
        ),
        assert(maxLength == null || maxLength > 0);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final InputDecoration? decoration;
  final TextStyle? style;
  final String? placeholder;
  final TextStyle? placeholderStyle;
  final TextAlign textAlign;
  final bool readOnly;
  final bool obscureText;
  final String obscuringCharacter;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;

  /// Callback invoked when text is pasted.
  /// Return `true` to indicate the paste was handled (skip default insertion).
  /// Return `false` or null to proceed with default insertion.
  final bool Function(String pastedText)? onPaste;

  /// Editor-level interception invoked before Cinder's built-in editing intents.
  final bool Function(KeyboardEvent event)? onEditorKeyEvent;

  /// Application shortcut handler invoked only after editor shortcuts decline.
  final bool Function(KeyboardEvent event)? onAppKeyEvent;

  /// Backwards-compatible alias for [onAppKeyEvent].
  final bool Function(KeyboardEvent event)? onKeyEvent;

  /// Configures the Enter chord used for submit/send.
  final TextFieldSubmitMode submitMode;

  /// Stable conversation/document identifier used for draft persistence.
  final Object? draftKey;

  /// Store used to persist and restore [draftKey].
  final TextDraftStore? draftStore;

  /// Removes the persisted draft after a successful submit callback.
  final bool clearDraftOnSubmit;

  final bool enabled;

  /// The color of the text cursor.
  ///
  /// If null, defaults to the theme's [TuiThemeData.primary] color.
  final Color? cursorColor;
  final CursorStyle cursorStyle;
  final Duration? cursorBlinkRate;

  /// The color of the text selection highlight.
  ///
  /// If null, defaults to the theme's [TuiThemeData.primary] color with
  /// reduced opacity.
  final Color? selectionColor;
  final bool showCursor;
  final double? width;
  final double? height;

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField> {
  late TextEditingController _controller;
  bool _controllerIsInternal = false;
  late FocusNode _focusNode;
  bool _focusNodeIsInternal = false;
  bool _hasFocus = false;
  Timer? _cursorTimer;
  bool _cursorVisible = true;
  int _viewOffset = 0; // For horizontal scrolling
  bool _restoringDraft = false;

  // Reference to the render object for cursor movement
  RenderTextField? _renderTextField;

  void _initFocusNode() {
    _focusNodeIsInternal = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextField');
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChanged);
  }

  void _disposeFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_focusNodeIsInternal) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus == _hasFocus) return;

    _hasFocus = hasFocus;
    if (hasFocus && widget.showCursor) {
      _startCursorBlink();
    } else {
      _stopCursorBlink();
    }
    widget.onFocusChange?.call(hasFocus);
    if (mounted) setState(() {});
  }

  void _handleSelectionChangeFromRenderObject(TextSelection newSelection) {
    setState(() {
      _controller.selection = newSelection;
    });
    // Mouse selection should focus the field, matching Flutter TextField.
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _initFocusNode();

    _attachController(widget.controller);
    _restoreDraft(widget.draftStore, widget.draftKey);
    _controller.addListener(_handleControllerChanged);

    if (_hasFocus && widget.showCursor) {
      _startCursorBlink();
    }
  }

  void _attachController(TextEditingController? controller) {
    _controllerIsInternal = controller == null;
    _controller = controller ?? TextEditingController();
  }

  void _persistDraft(TextDraftStore? store, Object? key) {
    if (_restoringDraft || store == null || key == null) return;
    store.write(key, _controller.value);
  }

  void _restoreDraft(
    TextDraftStore? store,
    Object? key, {
    bool clearWhenMissing = false,
  }) {
    if (store == null || key == null) return;
    final draft = store.read(key);
    if (draft == null && !clearWhenMissing) return;
    _restoringDraft = true;
    _controller.setValue(
      draft ?? const TextEditingValue.empty(),
      recordHistory: false,
    );
    _controller.clearHistory();
    _restoringDraft = false;
  }

  void _replaceEditingValue(String text, TextSelection selection) {
    _controller.value = TextEditingValue(text: text, selection: selection);
    _renderTextField?.resetTargetColumn();
  }

  @override
  void dispose() {
    _stopCursorBlink();
    _disposeFocusNode();
    _controller.removeListener(_handleControllerChanged);

    if (_controllerIsInternal) {
      _controller.dispose();
    }

    super.dispose();
  }

  void _handleControllerChanged() {
    _persistDraft(widget.draftStore, widget.draftKey);
    widget.onChanged?.call(_controller.text);
    setState(() {
      // Update view offset for horizontal scrolling
      _updateViewOffset();
    });
  }

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    final draftChanged = widget.draftKey != oldWidget.draftKey ||
        !identical(widget.draftStore, oldWidget.draftStore);

    if (controllerChanged || draftChanged) {
      _persistDraft(oldWidget.draftStore, oldWidget.draftKey);
    }

    if (controllerChanged) {
      _controller.removeListener(_handleControllerChanged);
      if (_controllerIsInternal) {
        _controller.dispose();
      }
      _attachController(widget.controller);
    }

    if (controllerChanged || draftChanged) {
      _restoreDraft(
        widget.draftStore,
        widget.draftKey,
        clearWhenMissing: draftChanged,
      );
    }

    if (controllerChanged) {
      _controller.addListener(_handleControllerChanged);
    }

    final focusNodeChanged = !identical(widget.focusNode, oldWidget.focusNode);
    if (focusNodeChanged) {
      _disposeFocusNode();
      _initFocusNode();
    }

    if (focusNodeChanged ||
        widget.cursorBlinkRate != oldWidget.cursorBlinkRate ||
        widget.showCursor != oldWidget.showCursor) {
      if (_hasFocus && widget.showCursor) {
        _startCursorBlink();
      } else {
        _stopCursorBlink();
      }
    }
  }

  void _startCursorBlink() {
    _cursorVisible = true;
    _cursorTimer?.cancel();

    // Check if blinking is disabled (null blink rate means static cursor)
    if (widget.cursorBlinkRate == null) {
      // Non-blinking cursor - always visible
      _cursorVisible = true;
      return;
    }

    // Start blinking with specified rate
    _cursorTimer = Timer.periodic(widget.cursorBlinkRate!, (timer) {
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
    });
  }

  void _stopCursorBlink() {
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _cursorVisible = false;
  }

  void _updateViewOffset() {
    // Simple horizontal scrolling for single-line fields
    if (widget.maxLines == 1 && widget.width != null) {
      final text = _controller.text;
      final cursorPos = _controller.selection.extentOffset;

      // Account for borders and padding to get actual content width
      final decoration = widget.decoration ?? const InputDecoration();
      final padding = decoration.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 1);
      final horizontalPadding = padding.left + padding.right;
      final borderWidth =
          decoration.border != null ? 2.0 : 0.0; // 1 on each side
      // Reserve 1 column for cursor display
      final maxVisibleWidth =
          (widget.width! - borderWidth - horizontalPadding - 1).toInt();

      if (maxVisibleWidth <= 0) return; // No space to display text

      // Calculate visual column position of cursor (accounting for wide characters)
      final textBeforeCursor = text.substring(
        0,
        math.min(cursorPos, text.length),
      );
      final cursorVisualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

      // Calculate visual width of currently visible text
      int viewOffsetVisualColumn = 0;
      if (_viewOffset > 0 && _viewOffset <= text.length) {
        viewOffsetVisualColumn = UnicodeWidth.stringWidth(
          text.substring(0, _viewOffset),
        );
      }

      // Adjust view offset to keep cursor visible
      if (cursorVisualColumn < viewOffsetVisualColumn) {
        // Cursor moved before visible area - scroll left
        // Find the character offset that corresponds to the cursor's visual position
        _viewOffset = cursorPos;
      } else if (cursorVisualColumn >=
          viewOffsetVisualColumn + maxVisibleWidth) {
        // Cursor moved after visible area - scroll right
        // We need to find a view offset such that the cursor is visible
        int newOffset = 0;
        int visualWidth = 0;

        // Find the rightmost offset that still shows the cursor
        final graphemes = text.characters.toList();
        for (int i = 0; i <= math.min(cursorPos, graphemes.length); i++) {
          if (i < graphemes.length) {
            final graphemeWidth = UnicodeWidth.graphemeWidth(graphemes[i]);
            if (cursorVisualColumn - visualWidth <= maxVisibleWidth - 1) {
              newOffset = i;
            }
            visualWidth += graphemeWidth;
          }
        }
        _viewOffset = newOffset;
      }
    }
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (!widget.enabled) return false;

    if (widget.onEditorKeyEvent?.call(event) ?? false) {
      return true;
    }

    final key = event.logicalKey;
    final controlOrMeta = event.isControlPressed || event.isMetaPressed;

    // Focus traversal is owned by Focus/FocusScope, not the editor.
    if (key == LogicalKey.tab) return false;

    // Modifier-specific editor commands must precede their unmodified keys.
    if (controlOrMeta && key == LogicalKey.keyZ) {
      final changed =
          event.isShiftPressed ? _controller.redo() : _controller.undo();
      if (changed) _renderTextField?.resetTargetColumn();
      return changed || _dispatchAppShortcut(event);
    }
    if (event.matches(LogicalKey.keyY, ctrl: true)) {
      final changed = _controller.redo();
      if (changed) _renderTextField?.resetTargetColumn();
      return changed || _dispatchAppShortcut(event);
    }
    if (controlOrMeta && key == LogicalKey.keyA) {
      _selectAll();
      return true;
    }
    if (controlOrMeta && key == LogicalKey.keyC) {
      if (!_controller.selection.isCollapsed) {
        _copy();
        return true;
      }
      return _dispatchAppShortcut(event);
    }
    if (controlOrMeta && key == LogicalKey.keyX) {
      if (!widget.readOnly && !_controller.selection.isCollapsed) {
        _cut();
        return true;
      }
      return _dispatchAppShortcut(event);
    }
    if (controlOrMeta && key == LogicalKey.keyV) {
      if (widget.readOnly) return _dispatchAppShortcut(event);
      _paste();
      return true;
    }
    if (!widget.readOnly && controlOrMeta && key == LogicalKey.backspace) {
      _deleteWordBackward();
      return true;
    }
    if (!widget.readOnly && controlOrMeta && key == LogicalKey.delete) {
      _deleteWordForward();
      return true;
    }
    if (controlOrMeta && event.isShiftPressed && key == LogicalKey.arrowLeft) {
      _moveCursorByWord(-1, true);
      return true;
    }
    if (controlOrMeta && event.isShiftPressed && key == LogicalKey.arrowRight) {
      _moveCursorByWord(1, true);
      return true;
    }
    if (controlOrMeta && key == LogicalKey.arrowLeft) {
      _moveCursorByWord(-1, false);
      return true;
    }
    if (controlOrMeta && key == LogicalKey.arrowRight) {
      _moveCursorByWord(1, false);
      return true;
    }
    if (!widget.readOnly && event.matches(LogicalKey.keyT, ctrl: true)) {
      _transposeCharacters();
      return true;
    }

    if (key == LogicalKey.enter || event.matches(LogicalKey.keyJ, ctrl: true)) {
      return _handleEnter(event);
    }

    if (key == LogicalKey.arrowLeft && event.isShiftPressed) {
      _moveCursor(-1, true);
      return true;
    }
    if (key == LogicalKey.arrowRight && event.isShiftPressed) {
      _moveCursor(1, true);
      return true;
    }
    if (key == LogicalKey.arrowUp &&
        event.isShiftPressed &&
        widget.maxLines != 1) {
      _moveCursorVertically(-1, true);
      return true;
    }
    if (key == LogicalKey.arrowDown &&
        event.isShiftPressed &&
        widget.maxLines != 1) {
      _moveCursorVertically(1, true);
      return true;
    }
    if (key == LogicalKey.arrowLeft) {
      _moveCursor(-1, false);
      return true;
    }
    if (key == LogicalKey.arrowRight) {
      _moveCursor(1, false);
      return true;
    }
    if (key == LogicalKey.arrowUp && widget.maxLines != 1) {
      _moveCursorVertically(-1, false);
      return true;
    }
    if (key == LogicalKey.arrowDown && widget.maxLines != 1) {
      _moveCursorVertically(1, false);
      return true;
    }
    if (key == LogicalKey.home) {
      _moveCursorToStart();
      return true;
    }
    if (key == LogicalKey.end) {
      _moveCursorToEnd();
      return true;
    }

    if (!widget.readOnly && key == LogicalKey.backspace) {
      _handleBackspace();
      return true;
    }
    if (!widget.readOnly && key == LogicalKey.delete) {
      _handleDelete();
      return true;
    }

    // Modified keys not claimed by the editor belong to the application.
    if (event.modifiers.hasAnyModifier && _dispatchAppShortcut(event)) {
      return true;
    }

    if (!widget.readOnly &&
        !controlOrMeta &&
        !event.isAltPressed &&
        event.character != null) {
      _insertText(event.character!);
      return true;
    }

    if (!widget.readOnly && !event.modifiers.hasAnyModifier) {
      final char = _getCharacterFromKey(key);
      if (char != null) {
        _insertText(char);
        return true;
      }
    }

    return _dispatchAppShortcut(event);
  }

  bool _dispatchAppShortcut(KeyboardEvent event) {
    final handler = widget.onAppKeyEvent ?? widget.onKeyEvent;
    return handler?.call(event) ?? false;
  }

  bool _handleEnter(KeyboardEvent event) {
    final isCtrlJ = event.matches(LogicalKey.keyJ, ctrl: true);
    final shouldSubmit = !isCtrlJ &&
        switch (widget.submitMode) {
          TextFieldSubmitMode.enter => !event.modifiers.hasAnyModifier,
          TextFieldSubmitMode.controlOrMetaEnter =>
            event.isControlPressed || event.isMetaPressed,
          TextFieldSubmitMode.shiftEnter => event.isShiftPressed,
          TextFieldSubmitMode.never => false,
        };

    if (shouldSubmit) {
      widget.onEditingComplete?.call();
      widget.onSubmitted?.call(_controller.text);
      if (widget.clearDraftOnSubmit &&
          widget.draftStore != null &&
          widget.draftKey != null) {
        widget.draftStore!.remove(widget.draftKey!);
      }
      return true;
    }

    if (!widget.readOnly && widget.maxLines != 1) {
      _insertText('\n');
      return true;
    }

    return _dispatchAppShortcut(event);
  }

  String? _getCharacterFromKey(LogicalKey key) {
    // Map common printable keys to characters
    if (key == LogicalKey.space) return ' ';
    if (key == LogicalKey.exclamation) return '!';
    if (key == LogicalKey.quoteDbl) return '"';
    if (key == LogicalKey.numberSign) return '#';
    if (key == LogicalKey.dollar) return '\$';
    if (key == LogicalKey.percent) return '%';
    if (key == LogicalKey.ampersand) return '&';
    if (key == LogicalKey.quoteSingle) return '\'';
    if (key == LogicalKey.parenthesisLeft) return '(';
    if (key == LogicalKey.parenthesisRight) return ')';
    if (key == LogicalKey.asterisk) return '*';
    if (key == LogicalKey.add) return '+';
    if (key == LogicalKey.comma) return ',';
    if (key == LogicalKey.minus) return '-';
    if (key == LogicalKey.period) return '.';
    if (key == LogicalKey.slash) return '/';
    if (key == LogicalKey.colon) return ':';
    if (key == LogicalKey.semicolon) return ';';
    if (key == LogicalKey.less) return '<';
    if (key == LogicalKey.equal) return '=';
    if (key == LogicalKey.greater) return '>';
    if (key == LogicalKey.question) return '?';
    if (key == LogicalKey.at) return '@';
    if (key == LogicalKey.bracketLeft) return '[';
    if (key == LogicalKey.backslash) return '\\';
    if (key == LogicalKey.bracketRight) return ']';
    if (key == LogicalKey.caret) return '^';
    if (key == LogicalKey.underscore) return '_';
    if (key == LogicalKey.backquote) return '`';
    if (key == LogicalKey.braceLeft) return '{';
    if (key == LogicalKey.bar) return '|';
    if (key == LogicalKey.braceRight) return '}';
    if (key == LogicalKey.tilde) return '~';

    // Digits
    if (key == LogicalKey.digit0) return '0';
    if (key == LogicalKey.digit1) return '1';
    if (key == LogicalKey.digit2) return '2';
    if (key == LogicalKey.digit3) return '3';
    if (key == LogicalKey.digit4) return '4';
    if (key == LogicalKey.digit5) return '5';
    if (key == LogicalKey.digit6) return '6';
    if (key == LogicalKey.digit7) return '7';
    if (key == LogicalKey.digit8) return '8';
    if (key == LogicalKey.digit9) return '9';

    // Letters - character is already provided in the event, this is just fallback
    // Note: This method is rarely used now since event.character is preferred

    return null;
  }

  void _insertText(String char) {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    // where text may have been modified externally (e.g., by onChanged callback)
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    // Check if we're at max length
    if (widget.maxLength != null) {
      final currentLength = text.characters.length;
      final insertLength = char.characters.length;
      final deleteLength = isCollapsed ? 0 : (clampedEnd - clampedStart);

      if (currentLength - deleteLength + insertLength > widget.maxLength!) {
        return;
      }
    }

    // Check max lines for multi-line fields
    if (widget.maxLines != null &&
        widget.maxLines! > 1 &&
        char.contains('\n')) {
      final currentLines = text.split('\n').length;
      final newLines = char.split('\n').length - 1;

      if (currentLines + newLines > widget.maxLines!) {
        return;
      }
    }

    String newText;
    int newOffset;

    if (!isCollapsed) {
      // Replace selected text
      newText =
          text.substring(0, clampedStart) + char + text.substring(clampedEnd);
      newOffset = clampedStart + char.length;
    } else {
      // Insert at cursor position
      newText = text.substring(0, clampedExtentOffset) +
          char +
          text.substring(clampedExtentOffset);
      newOffset = clampedExtentOffset + char.length;
    }

    _replaceEditingValue(newText, TextSelection.collapsed(offset: newOffset));
  }

  void _handleBackspace() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _replaceEditingValue(
        text.substring(0, clampedStart) + text.substring(clampedEnd),
        TextSelection.collapsed(offset: clampedStart),
      );
    } else if (clampedExtentOffset > 0) {
      // Delete the grapheme cluster before cursor
      final textBefore = text.substring(0, clampedExtentOffset);
      final textAfter = text.substring(clampedExtentOffset);

      // Use grapheme clusters to delete the entire cluster
      final graphemes = textBefore.characters;
      if (graphemes.isNotEmpty) {
        final newTextBefore = graphemes.skipLast(1).toString();
        _replaceEditingValue(
          newTextBefore + textAfter,
          TextSelection.collapsed(offset: newTextBefore.length),
        );
      }
    }
  }

  void _handleDelete() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _replaceEditingValue(
        text.substring(0, clampedStart) + text.substring(clampedEnd),
        TextSelection.collapsed(offset: clampedStart),
      );
    } else if (clampedExtentOffset < textLength) {
      // Delete the grapheme cluster after cursor
      final textBefore = text.substring(0, clampedExtentOffset);
      final textAfter = text.substring(clampedExtentOffset);

      // Use grapheme clusters to delete the entire cluster
      final graphemesAfter = textAfter.characters;
      if (graphemesAfter.isNotEmpty) {
        final newTextAfter = graphemesAfter.skip(1).toString();
        _replaceEditingValue(
          textBefore + newTextAfter,
          TextSelection.collapsed(offset: clampedExtentOffset),
        );
      }
    }
  }

  void _moveCursor(int delta, bool extendSelection) {
    _renderTextField?.moveCursorHorizontally(delta, extendSelection);
  }

  void _moveCursorByWord(int direction, bool extendSelection) {
    _renderTextField?.moveCursorByWord(direction, extendSelection);
  }

  bool _isSpace(String char) {
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }

  void _deleteWordBackward() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _replaceEditingValue(
        text.substring(0, clampedStart) + text.substring(clampedEnd),
        TextSelection.collapsed(offset: clampedStart),
      );
      return;
    }

    if (clampedExtentOffset == 0) return;

    int start = clampedExtentOffset;

    // Skip spaces backward
    while (start > 0 && _isSpace(text[start - 1])) {
      start--;
    }

    // Skip word characters backward
    while (start > 0 && !_isSpace(text[start - 1])) {
      start--;
    }

    _replaceEditingValue(
      text.substring(0, start) + text.substring(clampedExtentOffset),
      TextSelection.collapsed(offset: start),
    );
  }

  void _deleteWordForward() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Clamp selection offsets to valid range to handle race conditions
    final textLength = text.length;
    final clampedStart = selection.start.clamp(0, textLength);
    final clampedEnd = selection.end.clamp(0, textLength);
    final clampedExtentOffset = selection.extentOffset.clamp(0, textLength);
    final isCollapsed = clampedStart == clampedEnd;

    if (!isCollapsed) {
      // Delete selected text
      _replaceEditingValue(
        text.substring(0, clampedStart) + text.substring(clampedEnd),
        TextSelection.collapsed(offset: clampedStart),
      );
      return;
    }

    if (clampedExtentOffset >= textLength) return;

    int end = clampedExtentOffset;

    // Skip current word forward
    while (end < textLength && !_isSpace(text[end])) {
      end++;
    }

    // Skip spaces forward
    while (end < textLength && _isSpace(text[end])) {
      end++;
    }

    _replaceEditingValue(
      text.substring(0, clampedExtentOffset) + text.substring(end),
      TextSelection.collapsed(offset: clampedExtentOffset),
    );
  }

  void _transposeCharacters() {
    final text = _controller.text;
    final selection = _controller.selection;

    if (selection.extentOffset == 0 || text.length < 2) return;

    final chars = text.characters.toList();
    int pos = selection.extentOffset;

    // Find character positions
    int charCount = 0;
    int charIndex = 0;
    for (int i = 0; i < chars.length; i++) {
      if (charCount >= pos) {
        charIndex = i;
        break;
      }
      charCount += chars[i].length;
    }

    if (charIndex >= chars.length) {
      charIndex = chars.length - 1;
    }

    // Transpose characters
    if (charIndex > 0) {
      final temp = chars[charIndex - 1];
      chars[charIndex - 1] =
          chars[charIndex == chars.length ? charIndex - 1 : charIndex];
      chars[charIndex == chars.length ? charIndex - 1 : charIndex] = temp;

      final newText = chars.join();
      final newOffset =
          pos < text.length ? math.min(pos + 1, newText.length) : pos;
      _replaceEditingValue(newText, TextSelection.collapsed(offset: newOffset));
    }
  }

  void _moveCursorVertically(int direction, bool extendSelection) {
    _renderTextField?.moveCursorVertically(direction, extendSelection);
  }

  void _moveCursorToStart() {
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _renderTextField?.resetTargetColumn();
  }

  void _moveCursorToEnd() {
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _renderTextField?.resetTargetColumn();
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _copy() {
    // Copy selected text to clipboard using OSC 52
    if (!_controller.selection.isCollapsed) {
      final text = _controller.text;
      final selection = _controller.selection;

      // Clamp selection offsets to valid range to handle race conditions
      final textLength = text.length;
      final clampedStart = selection.start.clamp(0, textLength);
      final clampedEnd = selection.end.clamp(0, textLength);

      if (clampedStart < clampedEnd) {
        final selectedText = text.substring(clampedStart, clampedEnd);
        ClipboardManager.copy(selectedText);
      }
    }
  }

  void _cut() {
    // Copy selected text to clipboard and then delete it
    if (!_controller.selection.isCollapsed) {
      final text = _controller.text;
      final selection = _controller.selection;

      // Clamp selection offsets to valid range to handle race conditions
      final textLength = text.length;
      final clampedStart = selection.start.clamp(0, textLength);
      final clampedEnd = selection.end.clamp(0, textLength);

      if (clampedStart < clampedEnd) {
        final selectedText = text.substring(clampedStart, clampedEnd);

        // Copy to clipboard using OSC 52
        ClipboardManager.copy(selectedText);

        // Delete the selected text
        _replaceEditingValue(
          text.substring(0, clampedStart) + text.substring(clampedEnd),
          TextSelection.collapsed(offset: clampedStart),
        );
      }
    }
  }

  void _paste() {
    // Paste text from clipboard
    var clipboardText = ClipboardManager.paste();
    if (clipboardText != null && clipboardText.isNotEmpty) {
      if (widget.maxLines == 1) {
        // Single-line field: replace all newlines/carriage returns with spaces
        // This prevents accidentally submitting the form when pasting multi-line text
        clipboardText = clipboardText.replaceAll(RegExp(r'[\r\n]+'), ' ');
      } else {
        // Multi-line field: preserve newlines but normalize to \n only
        // Replace Windows-style \r\n and old Mac-style \r with Unix-style \n
        // Note: Pasting via Ctrl+V processes the text as a single string insertion,
        // so newlines won't trigger Enter key events or form submission
        clipboardText = clipboardText.replaceAll(RegExp(r'\r\n'), '\n');
        clipboardText = clipboardText.replaceAll(RegExp(r'\r'), '\n');
      }

      // Call onPaste callback if provided
      // If callback returns true, the paste was handled externally - skip default insertion
      final handled = widget.onPaste?.call(clipboardText) ?? false;
      if (!handled) {
        _insertText(clipboardText);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration ?? const InputDecoration();
    final isFocused = _hasFocus;

    // Prepare display text (for obscuring only)
    final actualText = _controller.text;
    String displayText = actualText;
    if (widget.obscureText) {
      displayText = widget.obscuringCharacter * displayText.length;
    }

    // Handle view offset for single-line fields
    if (widget.maxLines == 1 && widget.width != null) {
      final padding = decoration.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 1);
      final horizontalPadding = padding.left + padding.right;
      final borderWidth = decoration.border != null ? 2.0 : 0.0;
      // Reserve 1 column for cursor display
      final maxVisibleWidth =
          (widget.width! - borderWidth - horizontalPadding - 1).toInt();

      if (maxVisibleWidth > 0 && _viewOffset < displayText.length) {
        // Extract the visible portion based on visual width, not character count
        // We need to iterate through grapheme clusters, not individual chars
        final graphemes = displayText.characters.toList();

        if (_viewOffset < graphemes.length) {
          int startIdx = _viewOffset;
          int endIdx = _viewOffset;
          int visualWidth = 0;

          // Find how many graphemes fit in the visible width
          while (endIdx < graphemes.length && visualWidth < maxVisibleWidth) {
            final graphemeWidth = UnicodeWidth.graphemeWidth(graphemes[endIdx]);
            if (visualWidth + graphemeWidth <= maxVisibleWidth) {
              visualWidth += graphemeWidth;
              endIdx++;
            } else {
              break;
            }
          }

          // Reconstruct the visible text from graphemes
          displayText = graphemes.sublist(startIdx, endIdx).join();
        } else {
          displayText = '';
        }
      }
    }

    // Resolve colors from theme if not provided
    final theme = TuiTheme.of(context);
    final effectiveCursorColor = widget.cursorColor ?? theme.primary;
    final effectiveSelectionColor =
        widget.selectionColor ?? theme.primary.withOpacity(0.4);

    // Build the text field content
    Widget content = _TextFieldContent(
      text: actualText,
      placeholder: widget.placeholder,
      style: widget.style,
      placeholderStyle: widget.placeholderStyle,
      selection: _controller.selection,
      viewOffset: _viewOffset,
      cursorVisible: _cursorVisible && isFocused && widget.showCursor,
      cursorColor: effectiveCursorColor,
      cursorStyle: widget.cursorStyle,
      selectionColor: effectiveSelectionColor,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      isFocused: isFocused, // Pass focus state to render object
      obscureText: widget.obscureText,
      obscuringCharacter: widget.obscuringCharacter,
      onSelectionChange: _handleSelectionChangeFromRenderObject,
      onRenderObjectCreate: (renderObject) {
        _renderTextField = renderObject;
      },
    );

    // Apply decoration
    if (decoration.border != null || decoration.fillColor != null) {
      content = Container(
        width: widget.width,
        height: widget.height ?? (widget.maxLines ?? 1).toDouble() + 2,
        padding: decoration.contentPadding ??
            const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          border: isFocused
              ? decoration.focusedBorder ?? decoration.border
              : decoration.border,
          color: decoration.fillColor,
        ),
        child: content,
      );
    }

    // Focus owns traversal and keyboard dispatch for the field.
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _handleKeyEvent,
      child: content,
    );
  }
}

/// Internal widget for rendering text field content
class _TextFieldContent extends SingleChildRenderObjectWidget {
  const _TextFieldContent({
    required this.text,
    this.placeholder,
    this.style,
    this.placeholderStyle,
    required this.selection,
    required this.viewOffset,
    required this.cursorVisible,
    this.cursorColor,
    this.cursorStyle = CursorStyle.block,
    this.selectionColor,
    required this.textAlign,
    this.maxLines,
    required this.isFocused,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.onSelectionChange,
    this.onRenderObjectCreate,
  });

  final String text;
  final String? placeholder;
  final TextStyle? style;
  final TextStyle? placeholderStyle;
  final TextSelection selection;
  final int viewOffset;
  final bool cursorVisible;
  final Color? cursorColor;
  final CursorStyle cursorStyle;
  final Color? selectionColor;
  final TextAlign textAlign;
  final int? maxLines;
  final bool isFocused;
  final bool obscureText;
  final String obscuringCharacter;
  final void Function(TextSelection)? onSelectionChange;
  final void Function(RenderTextField)? onRenderObjectCreate;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final renderObject = RenderTextField(
      text: text,
      placeholder: placeholder,
      style: style,
      placeholderStyle: placeholderStyle,
      selection: selection,
      viewOffset: viewOffset,
      cursorVisible: cursorVisible,
      cursorColor: cursorColor,
      cursorStyle: cursorStyle,
      selectionColor: selectionColor,
      textAlign: textAlign,
      maxLines: maxLines,
      isFocused: isFocused,
      obscureText: obscureText,
      obscuringCharacter: obscuringCharacter,
      onSelectionChange: onSelectionChange,
    );
    onRenderObjectCreate?.call(renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(BuildContext context, RenderTextField renderObject) {
    renderObject
      ..text = text
      ..placeholder = placeholder
      ..style = style
      ..placeholderStyle = placeholderStyle
      ..selection = selection
      ..viewOffset = viewOffset
      ..cursorVisible = cursorVisible
      ..cursorColor = cursorColor
      ..cursorStyle = cursorStyle
      ..selectionColor = selectionColor
      ..textAlign = textAlign
      ..maxLines = maxLines
      ..isFocused = isFocused
      ..obscureText = obscureText
      ..obscuringCharacter = obscuringCharacter;
  }
}

/// Render object for text field
class RenderTextField extends RenderObject with MouseTrackerAnnotationProvider {
  RenderTextField({
    required String text,
    String? placeholder,
    TextStyle? style,
    TextStyle? placeholderStyle,
    required TextSelection selection,
    required int viewOffset,
    required bool cursorVisible,
    Color? cursorColor,
    CursorStyle cursorStyle = CursorStyle.block,
    Color? selectionColor,
    required TextAlign textAlign,
    int? maxLines,
    required bool isFocused,
    bool obscureText = false,
    String obscuringCharacter = '•',
    this.onSelectionChange,
  })  : _text = text,
        _placeholder = placeholder,
        _style = style,
        _placeholderStyle = placeholderStyle,
        _selection = selection,
        _viewOffset = viewOffset,
        _cursorVisible = cursorVisible,
        _cursorColor = cursorColor,
        _cursorStyle = cursorStyle,
        _selectionColor = selectionColor,
        _textAlign = textAlign,
        _maxLines = maxLines,
        _isFocused = isFocused,
        _obscureText = obscureText,
        _obscuringCharacter = obscuringCharacter {
    _updateMouseAnnotation();
  }

  String _text;
  String? _placeholder;
  TextStyle? _style;
  TextStyle? _placeholderStyle;
  TextSelection _selection;
  int _viewOffset;
  bool _cursorVisible;
  Color? _cursorColor;
  CursorStyle _cursorStyle;
  Color? _selectionColor;
  TextAlign _textAlign;

  @override
  bool hitTestSelf(Offset position) => true;
  int? _maxLines;
  bool _isFocused;
  bool _obscureText;
  String _obscuringCharacter;

  // Callback for selection changes
  final void Function(TextSelection)? onSelectionChange;

  // Store the layout result for proper Unicode rendering
  TextLayoutResult? _layoutResult;

  // Track target visual column for vertical movement
  int? _targetVisualColumn;

  // Mouse interaction state
  MouseTrackerAnnotation? _mouseAnnotation;
  bool _isLeftButtonPressed = false;
  int? _dragAnchorOffset;
  DateTime? _lastClickTime;
  int? _lastClickOffset;
  static const _doubleClickTimeout = Duration(milliseconds: 500);

  @override
  MouseTrackerAnnotation? get annotation => _mouseAnnotation;

  set text(String value) {
    if (_text != value) {
      _text = value;
      markNeedsLayout();
    }
  }

  set placeholder(String? value) {
    if (_placeholder != value) {
      _placeholder = value;
      markNeedsPaint();
    }
  }

  set style(TextStyle? value) {
    if (_style != value) {
      _style = value;
      markNeedsPaint();
    }
  }

  set placeholderStyle(TextStyle? value) {
    if (_placeholderStyle != value) {
      _placeholderStyle = value;
      markNeedsPaint();
    }
  }

  set selection(TextSelection value) {
    if (_selection != value) {
      _selection = value;
      markNeedsPaint();
    }
  }

  set viewOffset(int value) {
    if (_viewOffset != value) {
      _viewOffset = value;
      markNeedsPaint();
    }
  }

  set cursorVisible(bool value) {
    if (_cursorVisible != value) {
      _cursorVisible = value;
      markNeedsPaint();
    }
  }

  set cursorColor(Color? value) {
    if (_cursorColor != value) {
      _cursorColor = value;
      markNeedsPaint();
    }
  }

  set cursorStyle(CursorStyle value) {
    if (_cursorStyle != value) {
      _cursorStyle = value;
      markNeedsPaint();
    }
  }

  set selectionColor(Color? value) {
    if (_selectionColor != value) {
      _selectionColor = value;
      markNeedsPaint();
    }
  }

  set textAlign(TextAlign value) {
    if (_textAlign != value) {
      _textAlign = value;
      markNeedsPaint();
    }
  }

  set maxLines(int? value) {
    if (_maxLines != value) {
      _maxLines = value;
      markNeedsLayout();
    }
  }

  set isFocused(bool value) {
    if (_isFocused != value) {
      _isFocused = value;
      markNeedsPaint();
    }
  }

  set obscureText(bool value) {
    if (_obscureText != value) {
      _obscureText = value;
      markNeedsLayout();
    }
  }

  set obscuringCharacter(String value) {
    if (_obscuringCharacter != value) {
      _obscuringCharacter = value;
      if (_obscureText) {
        markNeedsLayout();
      }
    }
  }

  /// Move cursor horizontally
  void moveCursorHorizontally(int direction, bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorHorizontally(
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor vertically
  void moveCursorVertically(int direction, bool extendSelection) {
    if (_layoutResult == null) return;

    // Get current position if we don't have a target column
    if (_targetVisualColumn == null) {
      final currentPos = CursorMovement.getCursorPosition(
        layoutResult: _layoutResult!,
        text: _text,
        cursorOffset: _selection.extentOffset,
      );
      _targetVisualColumn = currentPos.visualColumn;
    }

    final newOffset = CursorMovement.moveCursorVertically(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
      targetVisualColumn: _targetVisualColumn!,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor by word
  void moveCursorByWord(int direction, bool extendSelection) {
    final newOffset = CursorMovement.moveCursorByWord(
      text: _text,
      currentOffset: _selection.extentOffset,
      direction: direction,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor to start of current line
  void moveCursorToLineStart(bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorToLineStart(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Move cursor to end of current line
  void moveCursorToLineEnd(bool extendSelection) {
    if (_layoutResult == null) return;

    final newOffset = CursorMovement.moveCursorToLineEnd(
      layoutResult: _layoutResult!,
      text: _text,
      currentOffset: _selection.extentOffset,
    );

    final newSelection = extendSelection
        ? _selection.copyWith(extentOffset: newOffset)
        : TextSelection.collapsed(offset: newOffset);

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null; // Reset target column
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  /// Reset target visual column (used when text changes)
  void resetTargetColumn() {
    _targetVisualColumn = null;
  }

  /// Returns the terminal screen coordinates (column, row) of the text cursor,
  /// or null if the cursor position cannot be determined or the field is not focused.
  ///
  /// This is used by the binding layer to position the physical terminal cursor
  /// so that IME (Input Method Editor) composition windows (e.g. Chinese Pinyin)
  /// appear at the correct location instead of flickering across the screen
  /// during differential rendering.
  ///
  /// The position is returned even when the cursor is in its blink-off phase
  /// so the IME window stays anchored at the correct location.
  Offset? getImeCursorPosition() {
    if (!_isFocused || _layoutResult == null) {
      return null;
    }

    final lines = _layoutResult!.lines;

    if (_text.isEmpty && _placeholder == null) {
      // Empty field - cursor at beginning
      final globalOffset = _globalPaintOffset;
      return Offset(globalOffset.dx, globalOffset.dy);
    }

    // Find which line the cursor is on (same logic as _paintCursor)
    int charCount = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length;

      if (charCount + lineLength >= _selection.extentOffset ||
          i == lines.length - 1) {
        final positionInLine = (_selection.extentOffset - charCount).clamp(
          0,
          lineLength,
        );

        // Calculate visual position using Unicode width
        final textBeforeCursor = line.substring(0, positionInLine);
        final visualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

        // Combine global offset with cursor position within the field
        final globalOffset = _globalPaintOffset;
        return Offset(globalOffset.dx + visualColumn, globalOffset.dy + i);
      }

      charCount += lineLength;
      // Only add 1 for actual newline characters, not wrapped lines.
      // Check the character right after this line's content in the
      // original text.
      if (i < lines.length - 1 &&
          charCount < _text.length &&
          _text[charCount] == '\n') {
        charCount++;
      }
    }

    return null;
  }

  // --- Mouse interaction ---

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _mouseAnnotation?.validForMouseTracker = true;
  }

  @override
  void detach() {
    _mouseAnnotation?.validForMouseTracker = false;
    super.detach();
  }

  @override
  bool hitTest(HitTestResult result, {required Offset position}) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    if (!bounds.contains(position)) return false;

    if (result is MouseHitTestResult && _mouseAnnotation != null) {
      result.addWithPosition(target: this, localPosition: position);
    }

    return hitTestSelf(position);
  }

  void _updateMouseAnnotation() {
    _mouseAnnotation = MouseTrackerAnnotation(
      onEnter: (event) {
        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown) {
            _isLeftButtonPressed = false;
          }
        }
      },
      onExit: (event) {
        if (_dragAnchorOffset != null) {
          // End drag when leaving the region, matching SelectionArea behavior.
          _handlePointerMove(event);
          _handlePointerUp(event);
        }
        _isLeftButtonPressed = false;
      },
      onHover: (event) {
        if (event.button == MouseButton.wheelUp ||
            event.button == MouseButton.wheelDown) {
          return;
        }

        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown && _isLeftButtonPressed) {
            _isLeftButtonPressed = false;
            _handlePointerUp(event);
          } else if (leftDown && _isLeftButtonPressed) {
            _handlePointerMove(event);
          }
        }
      },
      renderObject: this,
    );
  }

  Offset get _globalPaintOffset {
    double x = 0, y = 0;
    RenderObject? node = this;
    while (node != null) {
      if (node.parentData is BoxParentData) {
        final pd = node.parentData as BoxParentData;
        x += pd.offset.dx;
        y += pd.offset.dy;
      }
      node = node.parent;
    }
    return Offset(x, y);
  }

  int _getCharIndexFromMousePosition(int mouseX, int mouseY) {
    final gpo = _globalPaintOffset;
    final localX = mouseX - gpo.dx;
    final localY = mouseY - gpo.dy;

    // For obscured text, the layout lines contain obscuring characters (e.g. '•')
    // which may have different byte lengths than the real text. We must pass the
    // obscured text so character index computation matches the visual layout.
    final textForHitTest =
        _obscureText ? _obscuringCharacter * _text.length : _text;

    final charIndex = selection_utils.getCharacterIndexAtLocalPosition(
      localPos: Offset(localX, localY),
      text: textForHitTest,
      lines: _layoutResult?.lines ?? const [],
    );

    // For single-line fields with horizontal scrolling, the visible text starts
    // at _viewOffset but the layout contains the full text. The local x=0
    // corresponds to the character at _viewOffset, so we must add the offset.
    if (_maxLines == 1 && _viewOffset > 0) {
      return (charIndex + _viewOffset).clamp(0, _text.length);
    }

    return charIndex;
  }

  void _handlePointerDown(MouseEvent event) {
    if (_layoutResult == null) return;

    final charIndex = _getCharIndexFromMousePosition(event.x, event.y);
    final now = DateTime.now();

    // Double-click detection
    if (_lastClickTime != null &&
        _lastClickOffset != null &&
        now.difference(_lastClickTime!) < _doubleClickTimeout &&
        (_lastClickOffset! - charIndex).abs() <= 1) {
      _selectWordAt(charIndex);
      _lastClickTime = null;
      _lastClickOffset = null;
      _dragAnchorOffset = null;
      return;
    }

    // Single click - position cursor
    _lastClickTime = now;
    _lastClickOffset = charIndex;
    _dragAnchorOffset = charIndex;

    final newSelection = TextSelection.collapsed(offset: charIndex);
    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  void _handlePointerMove(MouseEvent event) {
    if (_dragAnchorOffset == null || _layoutResult == null) return;

    final charIndex = _getCharIndexFromMousePosition(event.x, event.y);

    final newSelection = TextSelection(
      baseOffset: _dragAnchorOffset!,
      extentOffset: charIndex,
    );

    if (newSelection != _selection) {
      _selection = newSelection;
      _targetVisualColumn = null;
      onSelectionChange?.call(newSelection);
      markNeedsPaint();
    }
  }

  void _handlePointerUp(MouseEvent event) {
    _dragAnchorOffset = null;
  }

  void _selectWordAt(int offset) {
    if (_text.isEmpty) return;
    final clampedOffset = offset.clamp(0, _text.length - 1);

    int start = clampedOffset;
    int end = clampedOffset;

    while (start > 0 && !_isWordBoundary(_text[start - 1])) {
      start--;
    }
    while (end < _text.length && !_isWordBoundary(_text[end])) {
      end++;
    }

    if (start == end) {
      // Double-click on whitespace/punctuation: just position cursor there
      final newSelection = TextSelection.collapsed(offset: clampedOffset);
      if (newSelection != _selection) {
        _selection = newSelection;
        _targetVisualColumn = null;
        onSelectionChange?.call(newSelection);
        markNeedsPaint();
      }
      return;
    }

    final newSelection = TextSelection(baseOffset: start, extentOffset: end);
    _selection = newSelection;
    _targetVisualColumn = null;
    onSelectionChange?.call(newSelection);
    markNeedsPaint();
  }

  static bool _isWordBoundary(String char) {
    // Treat whitespace and common punctuation as word boundaries
    const boundaries = {
      ' ',
      '\t',
      '\n',
      '\r',
      '.',
      ',',
      ';',
      ':',
      '!',
      '?',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '<',
      '>',
      '"',
      "'",
      '/',
      '\\',
      '|',
      '-',
      '+',
      '=',
      '*',
      '&',
      '^',
      '%',
      '#',
      '@',
      '~',
      '`',
    };
    return boundaries.contains(char);
  }

  @override
  void performLayout() {
    // Use TextLayoutEngine for proper Unicode text wrapping
    String textToLayout =
        _text.isEmpty && _placeholder != null ? _placeholder! : _text;

    // Apply text obscuring if needed
    if (_obscureText && _text.isNotEmpty) {
      textToLayout = _obscuringCharacter * _text.length;
    }

    // Reserve 1 column for the cursor block to be displayed within bounds
    // This ensures the cursor doesn't appear to go "into the wall" at line ends
    final availableWidth =
        constraints.maxWidth.isFinite ? constraints.maxWidth.toInt() : 80;
    final maxWidth = (availableWidth - 1)
        .clamp(1, double.infinity)
        .toInt(); // Reserve space for cursor

    final config = TextLayoutConfig(
      softWrap: _maxLines != 1, // Enable wrapping for multi-line fields
      overflow: TextOverflow.clip,
      textAlign: _textAlign,
      maxLines: _maxLines,
      maxWidth: maxWidth,
    );

    _layoutResult = TextLayoutEngine.layout(textToLayout, config);

    // Size based on actual layout result
    final actualHeight = _layoutResult!.actualHeight.toDouble();
    size = constraints.constrain(Size(constraints.maxWidth, actualHeight));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);

    if (_layoutResult == null) return;

    final textStyle = _text.isEmpty && _placeholder != null
        ? (_placeholderStyle ?? TextStyle(color: Colors.gray))
        : (_style ?? const TextStyle());

    final lines = _layoutResult!.lines;
    final alignmentWidth = size.width.toInt();

    // Paint each line from the layout result
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Calculate horizontal offset based on text alignment
      final xOffset = offset.dx +
          TextLayoutEngine.calculateAlignmentOffset(
            line,
            alignmentWidth,
            _textAlign,
          );

      // Apply justification if needed
      String displayLine = line;
      if (_textAlign == TextAlign.justify && i < lines.length - 1) {
        displayLine = TextLayoutEngine.justifyLine(
          line,
          alignmentWidth,
          isLastLine: false,
        );
      }

      _paintLineWithSelection(
        canvas,
        Offset(xOffset, offset.dy + i),
        displayLine,
        textStyle,
        i,
      );
    }

    // Paint cursor only for the focused field
    if (_cursorVisible && _isFocused) {
      _paintCursor(canvas, offset);
    }
  }

  void _paintLineWithSelection(
    TerminalCanvas canvas,
    Offset offset,
    String line,
    TextStyle style,
    int lineIndex,
  ) {
    selection_utils.paintTextWithSelection(
      canvas: canvas,
      offset: offset,
      line: line,
      style: style,
      lineIndex: lineIndex,
      text: _text,
      lines: _layoutResult?.lines ?? const [],
      selectionStart: _selection.isCollapsed ? null : _selection.start,
      selectionEnd: _selection.isCollapsed ? null : _selection.end,
      selectionColor: _selectionColor ?? Colors.blue,
    );
  }

  void _paintCursor(TerminalCanvas canvas, Offset offset) {
    if (_layoutResult == null) return;

    final cursorColor = _cursorColor ?? Colors.white;
    final lines = _layoutResult!.lines;

    if (_text.isEmpty && _placeholder == null) {
      // Empty field - show cursor at beginning
      _drawCursorAtPosition(canvas, offset, ' ', 0, cursorColor);
      return;
    }

    // Find which line the cursor is on
    int charCount = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineLength = line.length;

      // Check if cursor is on this line
      if (charCount + lineLength >= _selection.extentOffset ||
          i == lines.length - 1) {
        final positionInLine = (_selection.extentOffset - charCount).clamp(
          0,
          lineLength,
        );

        // Calculate visual position using Unicode width
        final textBeforeCursor = line.substring(0, positionInLine);
        final visualColumn = UnicodeWidth.stringWidth(textBeforeCursor);

        final cursorOffset =
            offset + Offset(visualColumn.toDouble(), i.toDouble());

        // Get the character at cursor position (or space if at end)
        final charAtCursor =
            positionInLine < line.length ? line[positionInLine] : ' ';

        _drawCursorAtPosition(
          canvas,
          cursorOffset,
          charAtCursor,
          positionInLine,
          cursorColor,
        );
        break;
      }

      charCount += lineLength;
      // Only add 1 for actual newline characters, not wrapped lines.
      // Check the character right after this line's content in the
      // original text — if it's a newline, the layout engine split
      // on it, so we must account for the extra byte.
      if (i < lines.length - 1 &&
          charCount < _text.length &&
          _text[charCount] == '\n') {
        charCount++;
      }
    }
  }

  void _drawCursorAtPosition(
    TerminalCanvas canvas,
    Offset position,
    String charUnderCursor,
    int cursorPos,
    Color cursorColor,
  ) {
    switch (_cursorStyle) {
      case CursorStyle.block:
        // Filled block - traditional terminal cursor
        final blockStyle = TextStyle(
          color: Colors.black,
          backgroundColor: cursorColor,
        );
        canvas.drawText(position, charUnderCursor, style: blockStyle);
        break;

      case CursorStyle.underline:
        // Draw the character with underline decoration
        final underlineStyle = TextStyle(
          color: _style?.color ?? Colors.white,
          backgroundColor: _style?.backgroundColor,
          decoration: TextDecoration.underline,
        );
        canvas.drawText(position, charUnderCursor, style: underlineStyle);
        break;

      case CursorStyle.blockOutline:
        // Draw block outline - invert the colors
        final outlineStyle = TextStyle(
          color: Colors.black,
          backgroundColor: cursorColor,
        );
        canvas.drawText(position, charUnderCursor, style: outlineStyle);
        break;
    }
  }
}

/// Input decoration for text fields
class InputDecoration {
  const InputDecoration({
    this.hintText,
    this.labelText,
    this.helperText,
    this.errorText,
    this.prefixText,
    this.suffixText,
    this.counter,
    this.filled,
    this.fillColor,
    this.border,
    this.focusedBorder,
    this.errorBorder,
    this.contentPadding,
  });

  final String? hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final String? prefixText;
  final String? suffixText;
  final Widget? counter;
  final bool? filled;
  final Color? fillColor;
  final BoxBorder? border;
  final BoxBorder? focusedBorder;
  final BoxBorder? errorBorder;
  final EdgeInsets? contentPadding;
}

// TextAlign is now imported from text_layout_engine.dart

/// Cursor style options for the text field
enum CursorStyle {
  /// A filled block cursor (default terminal style)
  block,

  /// An underline cursor
  underline,

  /// An outlined block cursor
  blockOutline,
}

/// Type definitions
typedef ValueChanged<T> = void Function(T value);
