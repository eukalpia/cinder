import '../components/focus.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';

/// Describes a user intention independently from the input that triggered it.
abstract class Intent {
  const Intent();
}

/// A named intention useful for application commands and menus.
final class NamedIntent extends Intent {
  const NamedIntent(this.name, {this.arguments = const <String, Object?>{}});

  final String name;
  final Map<String, Object?> arguments;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NamedIntent &&
            other.name == name &&
            _mapsEqual(other.arguments, arguments);
  }

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAllUnordered(arguments.entries));
}

/// Performs an operation for an [Intent].
abstract class Action<T extends Intent> {
  const Action();

  bool isEnabled(covariant T intent) => true;

  Object? invoke(covariant T intent);
}

final class CallbackAction<T extends Intent> extends Action<T> {
  const CallbackAction({required this.onInvoke, this.enabled});

  final Object? Function(T intent) onInvoke;
  final bool Function(T intent)? enabled;

  @override
  bool isEnabled(T intent) => enabled?.call(intent) ?? true;

  @override
  Object? invoke(T intent) => onInvoke(intent);
}

/// Dispatches actions and provides one customization point for instrumentation.
class ActionDispatcher {
  const ActionDispatcher();

  Object? invokeAction(Action<dynamic> action, Intent intent) {
    if (!action.isEnabled(intent)) return null;
    return action.invoke(intent);
  }
}

/// Makes actions available to descendants.
class Actions extends InheritedWidget {
  Actions({
    super.key,
    required Map<Type, Action<dynamic>> actions,
    this.dispatcher = const ActionDispatcher(),
    required super.child,
  }) : actions = Map<Type, Action<dynamic>>.unmodifiable(actions);

  final Map<Type, Action<dynamic>> actions;
  final ActionDispatcher dispatcher;

  static Actions? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<Actions>();
  }

  static Action<T>? find<T extends Intent>(BuildContext context) {
    BuildContext? cursor = context;
    while (cursor != null) {
      final scope = cursor.dependOnInheritedWidgetOfExactType<Actions>();
      final action = scope?.actions[T];
      if (action is Action<T>) return action;
      cursor = cursor.parent;
    }
    return null;
  }

  static bool isEnabled(BuildContext context, Intent intent) {
    final resolved = _resolve(context, intent);
    return resolved != null && resolved.action.isEnabled(intent);
  }

  static Object? invoke(BuildContext context, Intent intent) {
    final resolved = _resolve(context, intent);
    if (resolved == null) {
      throw StateError('No action registered for ${intent.runtimeType}.');
    }
    return resolved.scope.dispatcher.invokeAction(resolved.action, intent);
  }

  static Object? maybeInvoke(BuildContext context, Intent intent) {
    final resolved = _resolve(context, intent);
    if (resolved == null || !resolved.action.isEnabled(intent)) return null;
    return resolved.scope.dispatcher.invokeAction(resolved.action, intent);
  }

  static _ResolvedAction? _resolve(BuildContext context, Intent intent) {
    Element? cursor = context as Element?;
    while (cursor != null) {
      final element = cursor.getElementForInheritedWidgetOfExactType<Actions>();
      final scope = element?.widget as Actions?;
      final action = scope?.actions[intent.runtimeType];
      if (scope != null && action != null) {
        return _ResolvedAction(scope, action);
      }
      cursor = cursor.parent;
    }
    return null;
  }

  @override
  bool updateShouldNotify(Actions oldWidget) {
    return dispatcher != oldWidget.dispatcher || actions != oldWidget.actions;
  }
}

final class _ResolvedAction {
  const _ResolvedAction(this.scope, this.action);

  final Actions scope;
  final Action<dynamic> action;
}

/// Matches a keyboard event.
abstract interface class ShortcutActivator {
  const ShortcutActivator();

  bool accepts(KeyboardEvent event);

  String get label;
}

final class SingleActivator implements ShortcutActivator {
  const SingleActivator(
    this.trigger, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.includeRepeats = true,
  });

  final LogicalKey trigger;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  final bool includeRepeats;

  @override
  bool accepts(KeyboardEvent event) {
    if (!includeRepeats && event.isRepeat) return false;
    if (event.isUp) return false;
    return event.logicalKey == trigger &&
        event.modifiers.ctrl == control &&
        event.modifiers.shift == shift &&
        event.modifiers.alt == alt &&
        event.modifiers.meta == meta;
  }

  @override
  String get label {
    final parts = <String>[];
    if (control) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Meta');
    parts.add(_keyLabel(trigger));
    return parts.join('+');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SingleActivator &&
            trigger == other.trigger &&
            control == other.control &&
            shift == other.shift &&
            alt == other.alt &&
            meta == other.meta &&
            includeRepeats == other.includeRepeats;
  }

  @override
  int get hashCode =>
      Object.hash(trigger, control, shift, alt, meta, includeRepeats);
}

/// Ordered shortcut map. More recently registered entries win.
final class ShortcutManager {
  ShortcutManager([Map<ShortcutActivator, Intent> shortcuts = const {}])
      : _shortcuts = Map<ShortcutActivator, Intent>.of(shortcuts);

  final Map<ShortcutActivator, Intent> _shortcuts;

  Map<ShortcutActivator, Intent> get shortcuts =>
      Map<ShortcutActivator, Intent>.unmodifiable(_shortcuts);

  set shortcuts(Map<ShortcutActivator, Intent> value) {
    _shortcuts
      ..clear()
      ..addAll(value);
  }

  Intent? find(KeyboardEvent event) {
    for (final entry in _shortcuts.entries.toList(growable: false).reversed) {
      if (entry.key.accepts(event)) return entry.value;
    }
    return null;
  }
}

/// Converts key events into intents and dispatches them through [Actions].
class Shortcuts extends StatelessWidget {
  Shortcuts({
    super.key,
    required Map<ShortcutActivator, Intent> shortcuts,
    this.manager,
    this.autofocus = false,
    required this.child,
  }) : shortcuts = Map<ShortcutActivator, Intent>.unmodifiable(shortcuts);

  final Map<ShortcutActivator, Intent> shortcuts;
  final ShortcutManager? manager;
  final bool autofocus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveManager = manager ?? ShortcutManager(shortcuts);
    if (manager != null && manager!.shortcuts != shortcuts) {
      manager!.shortcuts = shortcuts;
    }
    return Focus(
      autofocus: autofocus,
      skipTraversal: true,
      onKeyEvent: (event) {
        final intent = effectiveManager.find(event);
        if (intent == null) return false;
        final action = Actions._resolve(context, intent);
        if (action == null || !action.action.isEnabled(intent)) return false;
        action.scope.dispatcher.invokeAction(action.action, intent);
        return true;
      },
      child: child,
    );
  }
}

/// Metadata shared by command palettes, menus, and toolbars.
final class Command {
  const Command({
    required this.id,
    required this.label,
    required this.intent,
    this.description,
    this.category,
    this.shortcut,
    this.keywords = const <String>[],
    this.enabled = true,
  });

  final String id;
  final String label;
  final String? description;
  final String? category;
  final Intent intent;
  final ShortcutActivator? shortcut;
  final List<String> keywords;
  final bool enabled;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String>[
      id,
      label,
      if (description != null) description!,
      if (category != null) category!,
      ...keywords,
    ].join(' ').toLowerCase();
    return normalized
        .split(RegExp(r'\s+'))
        .every((token) => haystack.contains(token));
  }
}

class CommandScope extends InheritedWidget {
  CommandScope({
    super.key,
    required List<Command> commands,
    required super.child,
  }) : commands = List<Command>.unmodifiable(commands);

  final List<Command> commands;

  static List<Command> of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CommandScope>()
            ?.commands ??
        const <Command>[];
  }

  static List<Command> search(BuildContext context, String query) {
    return of(context).where((command) => command.matches(query)).toList();
  }

  @override
  bool updateShouldNotify(CommandScope oldWidget) =>
      commands != oldWidget.commands;
}

bool _mapsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

String _keyLabel(LogicalKey key) {
  final name = key.debugName;
  if (name.startsWith('key') && name.length == 4) {
    return name.substring(3).toUpperCase();
  }
  if (name.startsWith('digit') && name.length == 6) {
    return name.substring(5);
  }
  return switch (key) {
    LogicalKey.space => 'Space',
    LogicalKey.enter => 'Enter',
    LogicalKey.escape => 'Esc',
    LogicalKey.tab => 'Tab',
    LogicalKey.backspace => 'Backspace',
    LogicalKey.delete => 'Delete',
    LogicalKey.arrowUp => 'Up',
    LogicalKey.arrowDown => 'Down',
    LogicalKey.arrowLeft => 'Left',
    LogicalKey.arrowRight => 'Right',
    _ => name,
  };
}
