# Custom render objects

Custom render objects are the lowest-level extension point for layout, paint, hit testing, and cached-layer integration. Use them only when existing widget composition is insufficient.

## Widget/element/render-object pattern

```dart
class Sparkline extends LeafRenderObjectWidget {
  const Sparkline({super.key, required this.values, required this.style});

  final List<double> values;
  final TextStyle style;

  @override
  RenderSparkline createRenderObject(BuildContext context) {
    return RenderSparkline(values: values, style: style);
  }

  @override
  void updateRenderObject(BuildContext context, RenderSparkline renderObject) {
    renderObject
      ..values = values
      ..style = style;
  }
}
```

Setters choose invalidation:

```dart
set values(List<double> value) {
  if (listEquals(_values, value)) return;
  _values = List.unmodifiable(value);
  markNeedsPaint(); // layout if geometry depends on values
}
```

Never mutate public input collections in place without invalidation.

## Choose the correct mark

```text
markNeedsLayout       geometry/size/child positions may change
markNeedsPaint        cells/colors/text change in same geometry
markNeedsCompositing  layer placement/effect changes
markNeedsBuild        widget configuration must rebuild
```

`markNeedsLayout` implies paint. Do not call all marks defensively. Current API lacks `markNeedsCompositing`; until added, use the framework's conservative invalidation.

## Layout

Leaf:

```dart
@override
void performLayout() {
  size = constraints.constrain(const Size(20, 5));
}
```

Parent:

```dart
@override
void performLayout() {
  child?.layout(childConstraints, parentUsesSize: true);
  final data = child?.parentData as BoxParentData?;
  data?.offset = const Offset(0, 0);
  size = constraints.constrain(child?.size ?? Size.zero);
}
```

Always set finite constrained size, lay out child before reading size, initialize parent data in `setupParentData`, avoid cell writes/state mutation/async work, document cache invalidation, and handle zero/tight/unbounded constraints.

## Paint

```dart
@override
void paint(TerminalCanvas canvas, Offset offset) {
  final local = canvas.clip(
    Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
  );
  local.drawText(Offset.zero, '...');
  super.paint(canvas, offset);
}
```

Follow the established coordinate convention; do not add offset twice.

Requirements:

- paint only through canvas;
- preserve clips;
- use complete grapheme strings;
- never write ANSI;
- paint children at parent-data offsets;
- call `super.paint` for dirty-state contract;
- avoid allocations in per-cell hot loops;
- never schedule state changes during paint.

## Wide graphemes

Prefer `drawText`. Manual painters must segment graphemes, use Cinder width policy, write leader/continuation atomically, normalize intersecting old pairs, and avoid partial width-2 writes. Direct buffer access is unsupported.

## Paint bounds

If painting outside `size`, expose conservative paint bounds once API exists. Until then use a containing clip/boundary large enough to cover effects and invalidate the containing bounds. Glow, shadows, particles, and overflow commonly under-damage.

## Children

A multi-child render object adopts/drops through framework helpers, maintains order, initializes parent data, visits every child, detaches/disposes correctly, marks layout on add/remove/reorder, and hit-tests reverse paint order where topmost-first is required. A child cannot belong to two parents.

## Repaint boundaries

Use a boundary when subtree paint is expensive, content is often static, layer memory is justified, and bounds are stable. Prefer public `RepaintBoundary`. Specialized boundaries must satisfy ownership, image metadata, and transactional cache rules.

## Hit testing

Use local coordinates and valid layout size; transform for child offsets; test visual z-order; do not depend on paint side effects; map a continuation to its leading grapheme/widget position.

## Scrolling/images

Custom full-width viewports may request hardware scroll only under [`scroll-regions.md`](scroll-regions.md) and remain correct when rejected. Use `TerminalCanvas.drawImage`/public image widgets; never emit Kitty/Sixel/iTerm2/OSC/DCS from paint.

## Error behavior

The framework catches layout/paint errors, but custom objects should validate early and report runtime type, constraints/size, relevant properties, and child index/key. Do not silently ignore invariant failures that may corrupt cells/tree.

## Disposal

Release owned controllers/listeners, cached buffers/resources, image registrations, task handles, and child references through lifecycle. After dispose, never schedule frames.

## Testing checklist

Test create/update invalidation, every setter, min/max/tight/zero constraints, resize, child insertion/removal/reorder, clipping, wide Unicode/emoji, selection/hit test, cache behavior, first/differential/removal, exception fallback, disposal, and randomized reference-buffer comparison.

Useful assertions:

```text
paint-only update → layout count unchanged
layout update     → size/offset changed
unchanged update  → no frame scheduled
cached subtree    → child paint count unchanged
removed wide cell → both columns cleared
```

## Performance checklist

No full-screen work for local changes; no allocation per cell; reuse builders/buffers; avoid repeated grapheme segmentation/width work; cache with explicit invalidation; add benchmark for high-frequency objects.

## API stability

Stable docs distinguish public extension points, protected lifecycle, internal buffer/layer details, and debug-only hooks. Applications must not depend on private queues or front/back buffer identity.
