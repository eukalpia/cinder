import 'package:cinder/cinder.dart';

typedef Validator<T> = String? Function(T? value);
typedef FormFieldBuilder<T> =
    Widget Function(BuildContext context, FormFieldController<T> controller);

/// Common validation helpers.
abstract final class Validation {
  static Validator<T> required<T>([String message = 'This field is required']) {
    return (value) {
      if (value == null) return message;
      if (value is String && value.trim().isEmpty) return message;
      if (value is Iterable && value.isEmpty) return message;
      return null;
    };
  }

  static Validator<String> minLength(int length, [String? message]) {
    return (value) => value != null && value.length < length
        ? message ?? 'Must contain at least $length characters'
        : null;
  }

  static Validator<String> maxLength(int length, [String? message]) {
    return (value) => value != null && value.length > length
        ? message ?? 'Must contain at most $length characters'
        : null;
  }

  static Validator<String> pattern(
    RegExp expression, [
    String message = 'Invalid format',
  ]) {
    return (value) =>
        value != null && !expression.hasMatch(value) ? message : null;
  }

  static Validator<num> range(num minimum, num maximum, [String? message]) {
    return (value) => value != null && (value < minimum || value > maximum)
        ? message ?? 'Must be between $minimum and $maximum'
        : null;
  }

  static Validator<T> compose<T>(Iterable<Validator<T>> validators) {
    final list = List<Validator<T>>.unmodifiable(validators);
    return (value) {
      for (final validator in list) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}

abstract interface class FormFieldRegistration {
  Object? get valueObject;
  String? get errorText;
  bool validate();
  void reset();
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
}

/// Controller for a single [FormField].
class FormFieldController<T> extends ChangeNotifier
    implements FormFieldRegistration {
  FormFieldController({
    T? initialValue,
    Iterable<Validator<T>> validators = const [],
  }) : _initialValue = initialValue,
       _value = initialValue,
       _validators = List.of(validators);

  T? _initialValue;
  T? _value;
  List<Validator<T>> _validators;
  String? _errorText;
  bool _touched = false;

  T? get value => _value;
  set value(T? value) {
    if (_value == value) return;
    _value = value;
    _touched = true;
    notifyListeners();
  }

  @override
  Object? get valueObject => _value;

  @override
  String? get errorText => _errorText;
  bool get touched => _touched;
  bool get valid => _errorText == null;

  set validators(Iterable<Validator<T>> value) {
    _validators = List.of(value);
    validate();
  }

  void setInitialValue(T? value, {bool reset = false}) {
    _initialValue = value;
    if (reset) this.reset();
  }

  @override
  bool validate() {
    String? nextError;
    for (final validator in _validators) {
      nextError = validator(_value);
      if (nextError != null) break;
    }
    final changed = _errorText != nextError;
    _errorText = nextError;
    if (changed) notifyListeners();
    return nextError == null;
  }

  void setError(String? error) {
    if (_errorText == error) return;
    _errorText = error;
    notifyListeners();
  }

  @override
  void reset() {
    _value = _initialValue;
    _errorText = null;
    _touched = false;
    notifyListeners();
  }
}

/// Coordinates all fields inside a [Form].
class FormController extends ChangeNotifier {
  final Map<Object, FormFieldRegistration> _fields = {};

  Map<Object, Object?> get values => {
    for (final entry in _fields.entries) entry.key: entry.value.valueObject,
  };

  bool get valid => _fields.values.every((field) => field.errorText == null);
  int get fieldCount => _fields.length;

  void register(Object id, FormFieldRegistration controller) {
    final previous = _fields[id];
    if (identical(previous, controller)) return;
    if (previous != null) previous.removeListener(_changed);
    _fields[id] = controller;
    controller.addListener(_changed);
    notifyListeners();
  }

  void unregister(Object id, FormFieldRegistration controller) {
    if (!identical(_fields[id], controller)) return;
    _fields.remove(id);
    controller.removeListener(_changed);
    notifyListeners();
  }

  T? value<T>(Object id) => _fields[id]?.valueObject as T?;

  bool validate() {
    var result = true;
    for (final field in _fields.values) {
      if (!field.validate()) result = false;
    }
    notifyListeners();
    return result;
  }

  void reset() {
    for (final field in _fields.values) {
      field.reset();
    }
    notifyListeners();
  }

  void _changed() => notifyListeners();

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.removeListener(_changed);
    }
    _fields.clear();
    super.dispose();
  }
}

/// Provides a [FormController] to descendant fields.
class Form extends StatefulWidget {
  const Form({super.key, required this.child, this.controller, this.onChanged});

  final Widget child;
  final FormController? controller;
  final VoidCallback? onChanged;

  static FormController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_FormScope>()?.controller;
  }

  static FormController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No Form found in this context.');
    return controller!;
  }

  @override
  State<Form> createState() => _FormState();
}

class _FormState extends State<Form> {
  FormController? _owned;
  late FormController _controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _owned = widget.controller == null ? FormController() : null;
    _controller = widget.controller ?? _owned!;
    _controller.addListener(_changed);
  }

  void _detach() {
    _controller.removeListener(_changed);
    _owned?.dispose();
    _owned = null;
  }

  @override
  void didUpdateWidget(Form oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach();
      _attach();
    }
  }

  void _changed() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _FormScope(controller: _controller, child: widget.child);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

class _FormScope extends InheritedWidget {
  const _FormScope({required this.controller, required super.child});

  final FormController controller;

  @override
  bool updateShouldNotify(_FormScope oldWidget) {
    return !identical(oldWidget.controller, controller);
  }
}

/// Generic form field with validation and error presentation.
class FormField<T> extends StatefulWidget {
  const FormField({
    super.key,
    required this.id,
    required this.builder,
    this.controller,
    this.initialValue,
    this.validators = const [],
    this.label,
    this.helperText,
    this.showError = true,
    this.onChanged,
  });

  final Object id;
  final FormFieldBuilder<T> builder;
  final FormFieldController<T>? controller;
  final T? initialValue;
  final List<Validator<T>> validators;
  final String? label;
  final String? helperText;
  final bool showError;
  final ValueChanged<T?>? onChanged;

  @override
  State<FormField<T>> createState() => _FormFieldState<T>();
}

class _FormFieldState<T> extends State<FormField<T>> {
  FormFieldController<T>? _owned;
  late FormFieldController<T> _controller;
  FormController? _form;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  void _attachController() {
    _owned = widget.controller == null
        ? FormFieldController<T>(
            initialValue: widget.initialValue,
            validators: widget.validators,
          )
        : null;
    _controller = widget.controller ?? _owned!;
    _controller.validators = widget.validators;
    _controller.addListener(_changed);
  }

  void _detachController() {
    _form?.unregister(widget.id, _controller);
    _controller.removeListener(_changed);
    _owned?.dispose();
    _owned = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final form = Form.maybeOf(context);
    if (!identical(form, _form)) {
      _form?.unregister(widget.id, _controller);
      _form = form;
      _form?.register(widget.id, _controller);
    }
  }

  @override
  void didUpdateWidget(FormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detachController();
      _attachController();
      _form?.register(widget.id, _controller);
    } else {
      _controller.validators = widget.validators;
    }
    if (oldWidget.id != widget.id) {
      _form?.unregister(oldWidget.id, _controller);
      _form?.register(widget.id, _controller);
    }
  }

  void _changed() {
    widget.onChanged?.call(_controller.value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null)
          TerminalText.safe(
            widget.label!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        widget.builder(context, _controller),
        if (widget.showError && _controller.errorText != null)
          TerminalText.safe(
            _controller.errorText!,
            style: const TextStyle(color: Colors.red),
          )
        else if (widget.helperText != null)
          TerminalText.safe(
            widget.helperText!,
            style: const TextStyle(color: Colors.grey),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }
}

class AutocompleteItem<T> {
  const AutocompleteItem({required this.value, required this.label});
  final T value;
  final String label;
}

/// Text input with filtered suggestion selection.
class Autocomplete<T> extends StatefulWidget {
  const Autocomplete({
    super.key,
    required this.options,
    required this.onSelected,
    this.controller,
    this.displayStringForOption,
    this.placeholder = 'Type to search…',
    this.maxSuggestions = 8,
    this.autofocus = false,
  });

  final List<T> options;
  final ValueChanged<T> onSelected;
  final TextEditingController? controller;
  final String Function(T option)? displayStringForOption;
  final String placeholder;
  final int maxSuggestions;
  final bool autofocus;

  @override
  State<Autocomplete<T>> createState() => _AutocompleteState<T>();
}

class _AutocompleteState<T> extends State<Autocomplete<T>> {
  TextEditingController? _owned;
  late TextEditingController _controller;
  String _query = '';
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _owned = widget.controller == null ? TextEditingController() : null;
    _controller = widget.controller ?? _owned!;
    _query = _controller.text;
  }

  String _label(T option) {
    return widget.displayStringForOption?.call(option) ?? option.toString();
  }

  List<T> _suggestions() {
    final query = _query.trim().toLowerCase();
    final options = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => _label(option).toLowerCase().contains(query))
              .toList();
    return options.take(widget.maxSuggestions).toList(growable: false);
  }

  void _select(T option) {
    final label = _label(option);
    _controller.text = label;
    setState(() {
      _query = label;
      _selected = 0;
    });
    widget.onSelected(option);
  }

  bool _key(KeyboardEvent event) {
    final suggestions = _suggestions();
    if (event.logicalKey == LogicalKey.arrowDown) {
      if (suggestions.isNotEmpty) {
        setState(
          () => _selected = (_selected + 1).clamp(0, suggestions.length - 1),
        );
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      if (suggestions.isNotEmpty) {
        setState(
          () => _selected = (_selected - 1).clamp(0, suggestions.length - 1),
        );
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.enter && suggestions.isNotEmpty) {
      _select(suggestions[_selected.clamp(0, suggestions.length - 1)]);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          placeholder: widget.placeholder,
          onChanged: (value) => setState(() {
            _query = value;
            _selected = 0;
          }),
          onKeyEvent: _key,
        ),
        if (_query.isNotEmpty && suggestions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              border: BoxBorder.all(color: TuiTheme.of(context).outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < suggestions.length; index++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(suggestions[index]),
                    child: Container(
                      color: index == _selected
                          ? const Color.fromRGB(43, 49, 67)
                          : null,
                      child: TerminalText.safe(
                        _label(suggestions[index]),
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }
}

/// Alias-style autocomplete with typeahead naming.
class TypeAhead<T> extends Autocomplete<T> {
  const TypeAhead({
    super.key,
    required super.options,
    required super.onSelected,
    super.controller,
    super.displayStringForOption,
    super.placeholder,
    super.maxSuggestions,
    super.autofocus,
  });
}

class MultiSelectItem<T> {
  const MultiSelectItem({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// Keyboard-selectable multi-choice list.
class MultiSelect<T> extends StatefulWidget {
  const MultiSelect({
    super.key,
    required this.items,
    required this.values,
    required this.onChanged,
    this.autofocus = false,
    this.itemExtent = 1,
  });

  final List<MultiSelectItem<T>> items;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final bool autofocus;
  final double itemExtent;

  @override
  State<MultiSelect<T>> createState() => _MultiSelectState<T>();
}

class _MultiSelectState<T> extends State<MultiSelect<T>> {
  int _selected = 0;

  void _toggle(MultiSelectItem<T> item) {
    if (!item.enabled) return;
    final values = Set<T>.of(widget.values);
    if (!values.add(item.value)) values.remove(item.value);
    widget.onChanged(Set<T>.unmodifiable(values));
  }

  bool _key(KeyboardEvent event) {
    if (widget.items.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowDown) {
      setState(
        () => _selected = (_selected + 1).clamp(0, widget.items.length - 1),
      );
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      setState(
        () => _selected = (_selected - 1).clamp(0, widget.items.length - 1),
      );
      return true;
    }
    if (event.logicalKey == LogicalKey.space ||
        event.logicalKey == LogicalKey.enter) {
      _toggle(widget.items[_selected.clamp(0, widget.items.length - 1)]);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      child: VirtualListView.builder(
        itemCount: widget.items.length,
        itemExtent: widget.itemExtent,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final checked = widget.values.contains(item.value);
          Widget row = Row(
            children: [
              Text(checked ? '[x] ' : '[ ] '),
              Expanded(
                child: TerminalText.safe(
                  item.label,
                  style: TextStyle(color: item.enabled ? null : Colors.grey),
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
          if (index == _selected) {
            row = Container(color: const Color.fromRGB(43, 49, 67), child: row);
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _selected = index);
              _toggle(item);
            },
            child: row,
          );
        },
      ),
    );
  }
}

/// Boolean checkbox.
class Checkbox extends StatelessWidget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    void toggle() {
      if (enabled) onChanged(!value);
    }

    return Focus(
      autofocus: autofocus,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space ||
            event.logicalKey == LogicalKey.enter) {
          toggle();
          return enabled;
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value ? '[x]' : '[ ]',
              style: TextStyle(color: enabled ? Colors.cyan : Colors.grey),
            ),
            if (label != null) ...[
              const Text(' '),
              TerminalText.safe(
                label!,
                style: TextStyle(color: enabled ? null : Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Single radio option.
class Radio<T> extends StatelessWidget {
  const Radio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    this.enabled = true,
    this.autofocus = false,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T> onChanged;
  final String? label;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    void choose() {
      if (enabled) onChanged(value);
    }

    return Focus(
      autofocus: autofocus,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space ||
            event.logicalKey == LogicalKey.enter) {
          choose();
          return enabled;
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: choose,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? '(●)' : '( )',
              style: TextStyle(color: enabled ? Colors.cyan : Colors.grey),
            ),
            if (label != null) ...[
              const Text(' '),
              TerminalText.safe(
                label!,
                style: TextStyle(color: enabled ? null : Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Boolean switch.
class Switch extends StatelessWidget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    void toggle() {
      if (enabled) onChanged(!value);
    }

    return Focus(
      autofocus: autofocus,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space ||
            event.logicalKey == LogicalKey.enter ||
            event.logicalKey == LogicalKey.arrowLeft ||
            event.logicalKey == LogicalKey.arrowRight) {
          toggle();
          return enabled;
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value ? '[●──]' : '[──●]',
              style: TextStyle(
                color: enabled
                    ? (value ? Colors.green : Colors.grey)
                    : Colors.grey,
              ),
            ),
            if (label != null) ...[const Text(' '), TerminalText.safe(label!)],
          ],
        ),
      ),
    );
  }
}

/// Numeric slider with arrow-key control.
class Slider extends StatelessWidget {
  const Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.step,
    this.width = 24,
    this.showValue = true,
    this.autofocus = false,
  }) : assert(max > min),
       assert(width >= 3);

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double? step;
  final double width;
  final bool showValue;
  final bool autofocus;

  double get _effectiveStep => step ?? (max - min) / 20;

  void _set(double value) {
    onChanged(value.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final normalized = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final trackWidth = width.toInt().clamp(3, 10000);
    final thumb = (normalized * (trackWidth - 1)).round();
    final track = StringBuffer();
    for (var index = 0; index < trackWidth; index++) {
      track.write(
        index == thumb
            ? '●'
            : index < thumb
            ? '━'
            : '─',
      );
    }
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.arrowLeft ||
            event.logicalKey == LogicalKey.arrowDown) {
          _set(value - _effectiveStep);
          return true;
        }
        if (event.logicalKey == LogicalKey.arrowRight ||
            event.logicalKey == LogicalKey.arrowUp) {
          _set(value + _effectiveStep);
          return true;
        }
        if (event.logicalKey == LogicalKey.home) {
          _set(min);
          return true;
        }
        if (event.logicalKey == LogicalKey.end) {
          _set(max);
          return true;
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _set(value + _effectiveStep),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(track.toString(), style: const TextStyle(color: Colors.cyan)),
            if (showValue) ...[const Text(' '), Text(value.toStringAsFixed(2))],
          ],
        ),
      ),
    );
  }
}

class KeyChord {
  const KeyChord({required this.key, this.modifiers = const ModifierKeys()});

  final LogicalKey key;
  final ModifierKeys modifiers;

  factory KeyChord.fromEvent(KeyboardEvent event) {
    return KeyChord(key: event.logicalKey, modifiers: event.modifiers);
  }

  String get label {
    final parts = <String>[];
    if (modifiers.ctrl) parts.add('Ctrl');
    if (modifiers.shift) parts.add('Shift');
    if (modifiers.alt) parts.add('Alt');
    if (modifiers.meta) parts.add('Meta');
    parts.add(key.debugName.replaceFirst('key', '').toUpperCase());
    return parts.join('+');
  }

  @override
  bool operator ==(Object other) {
    return other is KeyChord &&
        key == other.key &&
        modifiers == other.modifiers;
  }

  @override
  int get hashCode => Object.hash(key, modifiers);
}

/// Captures the next keyboard chord.
class KeyRecorder extends StatefulWidget {
  const KeyRecorder({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Press shortcut',
    this.autofocus = false,
  });

  final KeyChord? value;
  final ValueChanged<KeyChord> onChanged;
  final String placeholder;
  final bool autofocus;

  @override
  State<KeyRecorder> createState() => _KeyRecorderState();
}

class _KeyRecorderState extends State<KeyRecorder> {
  bool _recording = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: (event) {
        if (!_recording && event.logicalKey != LogicalKey.enter) return false;
        if (!_recording) {
          setState(() => _recording = true);
          return true;
        }
        if (event.logicalKey == LogicalKey.escape) {
          setState(() => _recording = false);
          return true;
        }
        widget.onChanged(KeyChord.fromEvent(event));
        setState(() => _recording = false);
        return true;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _recording = true),
        child: Container(
          decoration: BoxDecoration(
            border: BoxBorder.all(
              color: _recording ? Colors.cyan : TuiTheme.of(context).outline,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: TerminalText.safe(
            _recording
                ? widget.placeholder
                : (widget.value?.label ?? widget.placeholder),
            style: TextStyle(color: _recording ? Colors.cyan : null),
          ),
        ),
      ),
    );
  }
}

class ShortcutBinding {
  const ShortcutBinding({required this.commandId, required this.chord});

  final Object commandId;
  final KeyChord chord;
}

/// Edits shortcut bindings for command IDs.
class ShortcutEditor extends StatelessWidget {
  const ShortcutEditor({
    super.key,
    required this.commands,
    required this.bindings,
    required this.onChanged,
  });

  final Map<Object, String> commands;
  final Map<Object, KeyChord?> bindings;
  final void Function(Object commandId, KeyChord chord) onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = commands.entries.toList(growable: false);
    return VirtualListView.builder(
      itemCount: entries.length,
      itemExtent: 2,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TerminalText.safe(
                    entry.value,
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: KeyRecorder(
                    value: bindings[entry.key],
                    onChanged: (chord) => onChanged(entry.key, chord),
                  ),
                ),
              ],
            ),
            const Divider(),
          ],
        );
      },
    );
  }
}
