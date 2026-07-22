import '../foundation/widget_state.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import '../semantics/semantics.dart';
import '../style.dart';
import '../theme/tui_theme.dart';
import 'basic.dart';
import 'focus.dart';
import 'gesture_detector.dart';
import 'mouse_region.dart';

/// Visual density for terminal controls.
enum ControlDensity { compact, standard, comfortable }

/// Shared styling contract for [Button].
class ButtonStyle {
  const ButtonStyle({
    this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
    this.textStyle,
    this.padding,
    this.borderStyle = BoxBorderStyle.rounded,
  });

  final WidgetStateProperty<Color?>? foregroundColor;
  final WidgetStateProperty<Color?>? backgroundColor;
  final WidgetStateProperty<Color?>? borderColor;
  final WidgetStateProperty<TextStyle?>? textStyle;
  final EdgeInsets? padding;
  final BoxBorderStyle borderStyle;

  Color? resolveForeground(Set<WidgetState> states) =>
      foregroundColor?.resolve(states);
  Color? resolveBackground(Set<WidgetState> states) =>
      backgroundColor?.resolve(states);
  Color? resolveBorder(Set<WidgetState> states) => borderColor?.resolve(states);
  TextStyle? resolveTextStyle(Set<WidgetState> states) =>
      textStyle?.resolve(states);
}

class _ButtonVisualScope extends InheritedWidget {
  const _ButtonVisualScope({required this.textStyle, required super.child});

  final TextStyle textStyle;

  static TextStyle of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_ButtonVisualScope>()
            ?.textStyle ??
        const TextStyle();
  }

  @override
  bool updateShouldNotify(_ButtonVisualScope oldWidget) =>
      textStyle != oldWidget.textStyle;
}

class _ButtonText extends StatelessWidget {
  const _ButtonText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: _ButtonVisualScope.of(context));
  }
}

/// A focusable, keyboard and pointer accessible terminal button.
class Button extends StatefulWidget {
  const Button({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.density = ControlDensity.standard,
  });

  factory Button.text(
    String label, {
    Key? key,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    bool autofocus = false,
    FocusNode? focusNode,
    String? semanticLabel,
    ControlDensity density = ControlDensity.standard,
  }) {
    return Button(
      key: key,
      onPressed: onPressed,
      style: style,
      autofocus: autofocus,
      focusNode: focusNode,
      semanticLabel: semanticLabel ?? label,
      density: density,
      child: _ButtonText(label),
    );
  }

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final ControlDensity density;

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  final WidgetStatesController _states = WidgetStatesController();

  bool get _enabled => widget.onPressed != null;

  void _setState(WidgetState state, bool enabled) {
    if (_states.update(state, enabled) && mounted) setState(() {});
  }

  bool _handleKey(KeyboardEvent event) {
    if (!_enabled) return false;
    if (event.logicalKey == LogicalKey.enter ||
        event.logicalKey == LogicalKey.space) {
      widget.onPressed?.call();
      return true;
    }
    return false;
  }

  EdgeInsets get _defaultPadding => switch (widget.density) {
        ControlDensity.compact => const EdgeInsets.symmetric(horizontal: 1),
        ControlDensity.standard => const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 0,
          ),
        ControlDensity.comfortable => const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 1,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    _states.update(WidgetState.disabled, !_enabled);
    final states = _states.value;
    final style = widget.style;

    final background = style?.resolveBackground(states) ??
        (states.contains(WidgetState.disabled)
            ? theme.surface
            : states.contains(WidgetState.pressed)
                ? theme.secondary
                : states.contains(WidgetState.focused) ||
                        states.contains(WidgetState.hovered)
                    ? theme.primary
                    : theme.surface);
    final foreground = style?.resolveForeground(states) ??
        (states.contains(WidgetState.disabled)
            ? theme.outline
            : background == theme.primary
                ? theme.onPrimary
                : background == theme.secondary
                    ? theme.onSecondary
                    : theme.onSurface);
    final borderColor = style?.resolveBorder(states) ??
        (states.contains(WidgetState.focused)
            ? theme.primary
            : states.contains(WidgetState.error)
                ? theme.error
                : theme.outline);
    final textStyle = (style?.resolveTextStyle(states) ?? const TextStyle())
        .copyWith(color: foreground);

    Widget content = _ButtonVisualScope(
      textStyle: textStyle,
      child: widget.child,
    );
    content = Container(
      padding: style?.padding ?? _defaultPadding,
      decoration: BoxDecoration(
        color: background,
        border: BoxBorder.all(
          color: borderColor,
          style: style?.borderStyle ?? BoxBorderStyle.rounded,
        ),
      ),
      child: content,
    );

    return Semantics(
      properties: SemanticsProperties(
        role: SemanticsRole.button,
        label: widget.semanticLabel,
        enabled: _enabled,
        focused: states.contains(WidgetState.focused),
      ),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: _enabled,
        onFocusChange: (value) => _setState(WidgetState.focused, value),
        onKeyEvent: _handleKey,
        child: MouseRegion(
          onEnter: (_) => _setState(WidgetState.hovered, true),
          onExit: (_) {
            _setState(WidgetState.hovered, false);
            _setState(WidgetState.pressed, false);
          },
          child: GestureDetector(
            onTapDown:
                _enabled ? (_) => _setState(WidgetState.pressed, true) : null,
            onTapUp:
                _enabled ? (_) => _setState(WidgetState.pressed, false) : null,
            onTapCancel:
                _enabled ? () => _setState(WidgetState.pressed, false) : null,
            onTap: widget.onPressed,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A focusable checkbox with deterministic terminal glyphs.
class Checkbox extends StatefulWidget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.tristate = false,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
  }) : assert(tristate || value != null);

  final bool? value;
  final void Function(bool?)? onChanged;
  final Widget? label;
  final bool tristate;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<Checkbox> {
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() {
    if (!_enabled) return;
    final next = widget.tristate
        ? switch (widget.value) {
            false => true,
            true => null,
            null => false,
          }
        : !(widget.value ?? false);
    widget.onChanged?.call(next);
  }

  bool _handleKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.space ||
        event.logicalKey == LogicalKey.enter) {
      _toggle();
      return _enabled;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final glyph = switch (widget.value) {
      true => '☑',
      false => '☐',
      null => '▣',
    };
    final color = !_enabled
        ? theme.outline
        : _focused || _hovered
            ? theme.primary
            : theme.onSurface;
    final mark = Text(glyph, style: TextStyle(color: color));
    final child = widget.label == null
        ? mark
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[mark, const SizedBox(width: 1), widget.label!],
          );

    return Semantics(
      properties: SemanticsProperties(
        role: SemanticsRole.checkbox,
        label: widget.semanticLabel,
        enabled: _enabled,
        focused: _focused,
        checked: widget.value,
      ),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: _enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: _handleKey,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child:
              GestureDetector(onTap: _enabled ? _toggle : null, child: child),
        ),
      ),
    );
  }
}

/// A compact boolean switch suitable for settings screens.
class Switch extends StatefulWidget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
  });

  final bool value;
  final void Function(bool)? onChanged;
  final Widget? label;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<Switch> createState() => _SwitchState();
}

class _SwitchState extends State<Switch> {
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged?.call(!widget.value);

  bool _handleKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.space ||
        event.logicalKey == LogicalKey.enter) {
      _toggle();
      return _enabled;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final trackColor = !_enabled
        ? theme.outlineVariant
        : widget.value
            ? theme.primary
            : theme.surface;
    final borderColor = _focused || _hovered ? theme.primary : theme.outline;
    final track = Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: trackColor,
        border: BoxBorder.all(
          color: borderColor,
          style: BoxBorderStyle.rounded,
        ),
      ),
      child: Text(
        widget.value ? '●  ' : '  ●',
        style: TextStyle(
          color: widget.value ? theme.onPrimary : theme.onSurface,
        ),
      ),
    );
    final child = widget.label == null
        ? track
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[track, const SizedBox(width: 1), widget.label!],
          );

    return Semantics(
      properties: SemanticsProperties(
        role: SemanticsRole.switchControl,
        label: widget.semanticLabel,
        enabled: _enabled,
        focused: _focused,
        checked: widget.value,
      ),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: _enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: _handleKey,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child:
              GestureDetector(onTap: _enabled ? _toggle : null, child: child),
        ),
      ),
    );
  }
}

/// Metadata for one tab.
class TabItem {
  const TabItem({required this.label, this.icon, this.enabled = true});

  final String label;
  final Widget? icon;
  final bool enabled;
}

/// Keyboard and pointer navigable horizontal tab bar.
class TabBar extends StatelessWidget {
  const TabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<TabItem> tabs;
  final int selectedIndex;
  final void Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var index = 0; index < tabs.length; index++)
          Padding(
            padding: const EdgeInsets.only(right: 1),
            child: Button(
              onPressed: tabs[index].enabled ? () => onSelected(index) : null,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) => index == selectedIndex
                      ? TuiTheme.of(context).primary
                      : states.contains(WidgetState.hovered)
                          ? TuiTheme.of(context).surface
                          : null,
                ),
                borderColor: WidgetStateProperty.all<Color?>(
                  index == selectedIndex
                      ? TuiTheme.of(context).primary
                      : TuiTheme.of(context).outlineVariant,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (tabs[index].icon != null) tabs[index].icon!,
                  if (tabs[index].icon != null) const SizedBox(width: 1),
                  Text(tabs[index].label),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Semantic status levels shared by badges and notifications.
enum StatusLevel { neutral, info, success, warning, error }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.level = StatusLevel.neutral});

  final String label;
  final StatusLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final background = switch (level) {
      StatusLevel.neutral => theme.surface,
      StatusLevel.info => theme.primary,
      StatusLevel.success => theme.success,
      StatusLevel.warning => theme.warning,
      StatusLevel.error => theme.error,
    };
    final foreground = switch (level) {
      StatusLevel.neutral => theme.onSurface,
      StatusLevel.info => theme.onPrimary,
      StatusLevel.success => theme.onSuccess,
      StatusLevel.warning => theme.onWarning,
      StatusLevel.error => theme.onError,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: background),
      child: Text(label, style: TextStyle(color: foreground)),
    );
  }
}
