# Cinder renderer contract

This file is the stable entry point for Cinder's normative rendering specification.
The detailed contract lives in [`doc/rendering/`](doc/rendering/overview.md).

## Normative status

The documents in `doc/rendering/` use the words **MUST**, **MUST NOT**, **SHOULD**,
**SHOULD NOT**, and **MAY** in their RFC 2119 sense. They define the behaviour that
Cinder's public rendering APIs and internal pipeline are required to preserve.

Implementation notes such as [`doc/renderer-v2.md`](doc/renderer-v2.md) describe a
particular release. When an implementation note conflicts with this contract, this
contract wins and the implementation is considered incomplete.

## Pipeline

```text
Input / Event
    ↓
State mutation
    ↓
Build
    ↓
Element reconciliation
    ↓
Layout
    ↓
Paint
    ↓
Layer composition
    ↓
Damage calculation
    ↓
Terminal diff
    ↓
Single batched stdout write
```

The pipeline is specified in:

- [Overview](doc/rendering/overview.md)
- [Frame pipeline](doc/rendering/frame-pipeline.md)
- [Cell buffer](doc/rendering/cell-buffer.md)
- [Damage tracking](doc/rendering/damage-tracking.md)
- [Layout and paint](doc/rendering/layout-and-paint.md)
- [Compositing](doc/rendering/compositing.md)
- [Terminal diff](doc/rendering/terminal-diff.md)
- [Images](doc/rendering/images.md)
- [Scroll regions](doc/rendering/scroll-regions.md)
- [Performance contract](doc/rendering/performance-contract.md)
- [Custom render objects](doc/rendering/custom-render-objects.md)
