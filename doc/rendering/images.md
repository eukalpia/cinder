# Images in the renderer

Images are part of render/composition, not raw escapes written by widgets. Cinder supports Kitty, iTerm2, Sixel, and Unicode-cell fallback. Protocol choice affects encoding/cleanup/clipping/scroll eligibility, not layout semantics.

## Logical model

```dart
final class ImagePlacement {
  Object identity;
  ImageProtocol protocol;
  RectI cellRect;
  Object encodedPayload;
  int generation;
  bool opaque;
}
```

Protocol-native images reserve `CellKind.imagePlaceholder`; bytes/identity are stored once in placement metadata. Unicode fallback uses ordinary cells.

## Pipeline

```text
Image widget state
      ↓
decode / resize / protocol selection
      ↓
RenderImage layout
      ↓
paint placeholders or Unicode cells
      ↓
compose placement metadata
      ↓
damage old/new rectangles
      ↓
diff/reconcile overlays
      ↓
single frame presentation
```

Decode/encode may run off the UI isolate; delivered results are immutable.

## Capability selection

Deterministic order:

1. explicit override;
2. Kitty;
3. iTerm2;
4. Sixel;
5. Unicode true-color half blocks;
6. quantized Unicode fallback.

Protocol change invalidates image caches and damages visible image regions.

## Layout

Image widgets declare cell width/height. Pixel dimensions and fit determine payload. Layout MUST NOT change merely because protocol/native fallback changes. Non-finite/negative dimensions are rejected or constrained to zero.

## Placeholder contract

- placeholders reserve full visible rectangle;
- no image bytes are duplicated per cell;
- text diff emits safe blanks where required;
- later text over placeholder invalidates overlapped placement or follows explicit z-order policy;
- placements cannot contain/partially cover wide continuations.

## Clipping

When clip cuts a native image, re-rasterize/re-encode cropped pixels, use equivalent protocol crop, or fall back to Unicode. Shrinking metadata while sending original uncropped payload is invalid. Cached layers carry only complete valid contained placements.

## Composition and z-order

Portable policy:

- cell content beneath visible native image is logically hidden;
- placements emit after conflicting text cleanup;
- later overlapping non-image layers require cleanup/re-emission or Unicode fallback;
- unsupported interleaving degrades safely rather than leaving detached artifacts;
- native IDs are used for update/delete where supported.

## Damage

Damage old rectangle on removal/move/resize, new rectangle on insertion/move/resize, changed pixels when incremental updates exist, cleanup-manager regions, protocol change, and layer clip/offset changes.

Unchanged identity, rect, protocol, generation, and payload need not re-emit.

## Cleanup

- Kitty: delete/update by ID where supported.
- iTerm2/Sixel: clear covered cells and repaint.
- Unicode: ordinary diff.

Cleanup commands are inside the same frame payload. Unmount schedules cleanup; it never writes terminal output directly.

## Scroll regions

Reject hardware scroll when a native image intersects unless tested protocol semantics and exact placement-model updates exist. Unicode fallback scrolls as cells. Conservative fallback is preferred.

## Caching

Caches may store decoded pixels, resized RGBA, protocol payload, Unicode cells, and IDs/generations. Keys include source hash, pixel/cell dimensions, fit/alignment, protocol, color profile, background, and crop.

Layer caches reference immutable payloads. Disposing a layer releases placement references but shared decoded cache may remain under its budget.

## Failure behavior

Decode failure renders an error placeholder. Encode failure falls back. Placement failure omits/cleans while preserving cell correctness. Cleanup uncertainty marks baseline unknown. Image failures never prevent terminal restoration.

## Security

Enforce decoded-size/pixel/decompression limits, trusted protocol encoders, no raw user DCS/APC/OSC, network timeout/redirect/content policy, and cache memory limits.

## Metrics

```text
visibleImages
imageCacheHits
imageCacheMisses
decodedBytes
encodedBytes
imagePlacementsEmitted
imageCleanups
unicodeFallbackCells
imageEncodeTime
```

## Current implementation status

Implemented: file/network/memory/RGBA widgets, protocol selection, native/Unicode paths, placeholders/pending metadata, cached-layer image translation, cleanup manager, unchanged-placement suppression, and scroll rejection for intersecting images.

Specified gaps: transactional image-state commit, complete clipping/cropping contracts, global cache budgets, and per-frame image metrics.
