import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:meta/meta.dart';
import 'package:cinder/src/components/basic.dart';
import 'package:cinder/src/foundation/persistent_hash_map.dart';
import 'package:cinder/src/foundation/cinder_error.dart';
import 'package:cinder/src/foundation/cancellation.dart';
import 'package:cinder/src/foundation/resource_scope.dart';
import 'package:cinder/src/rectangle.dart';
import 'package:cinder/src/size.dart';
import 'package:cinder/src/style.dart';

import 'terminal_canvas.dart';

part 'binding.dart';
part 'build_context.dart';
part 'build_owner.dart';
part 'buildable_element.dart';
part 'widget.dart';
part 'element.dart';
part 'keys.dart';
part 'proxy_element.dart';
part 'render_error_box.dart';
part 'render_object.dart';
part 'stateful_widget.dart';
part 'stateless_widget.dart';
part 'layout_builder.dart';

typedef WidgetBuilder = Widget Function(BuildContext context);
typedef StateSetter = void Function(VoidCallback fn);
typedef VoidCallback = void Function();
typedef ElementVisitor = void Function(Element element);

/// Base class for all TUI components (similar to Flutter's Widget)
@immutable
abstract class Widget {
  const Widget({this.key});

  final Key? key;

  @protected
  Element createElement();

  static bool canUpdate(Widget oldWidget, Widget newWidget) {
    return oldWidget.runtimeType == newWidget.runtimeType &&
        oldWidget.key == newWidget.key;
  }
}

abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  const SingleChildRenderObjectWidget({super.key, this.child});

  final Widget? child;

  @override
  SingleChildRenderObjectElement createElement() =>
      SingleChildRenderObjectElement(this);
}

abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  const MultiChildRenderObjectWidget({super.key, this.children = const []});

  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement() =>
      MultiChildRenderObjectElement(this);
}
