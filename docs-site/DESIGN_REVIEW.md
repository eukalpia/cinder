# Cinder web design review

## Visual thesis

The public site is a terminal control surface, not a SaaS landing page wearing terminal colors.

The browser still serves semantic HTML for documentation, navigation, accessibility, and search indexing. Product surfaces that claim to be Cinder applications are real Dart programs rendered by Cinder and hosted inside xterm.js.

## Information hierarchy

1. Show the real product: the live Cinder web runner.
2. Explain the programming model and render pipeline.
3. Show source beside runtime output.
4. Expose generated examples and engineering documents.
5. Explain browser/native limits at the point of use.
6. Provide installation and repository links without marketing detours.

## Composition

The homepage uses a dense terminal frame:

- indexed command-bar navigation;
- introduction pane;
- live Cinder scene;
- source and runtime panes;
- render-pipeline ledger;
- runtime guarantees;
- generated example index;
- source-backed documentation index;
- keyboard shortcut status bar.

Panels use straight borders and shared edges. They are not detached floating cards.

## Color system

- page: `#05070b`;
- panel: `#080b11`;
- border: `#29283a`;
- primary functional accent: ember `#ff8a2b`;
- restrained identity accent: violet `#a76cff`;
- success/runtime state: green `#72d572`;
- primary text: `#ded8e9`;
- muted text: `#888198`.

Orange indicates actions, transitions, and functional emphasis. Violet identifies Cinder, source metadata, and navigation indices. Green is reserved for real running/connected states.

## Typography

- metadata, runtime state, commands, navigation, code, and ledgers: monospace;
- long documentation remains readable and is not forced into tiny terminal text;
- homepage headings use the same monospace family at a larger size rather than a generic gradient display face.

## Borders and spacing

- no glass panels;
- no blur on terminal surfaces;
- no decorative border radius;
- 1px shared borders;
- 4–8px inter-panel gaps;
- compact metadata rows;
- generous line height only for explanatory prose.

## Motion

The only decorative motion is the cursor blink. The Cinder scene animation is product evidence: it is rendered by the real Cinder runtime. `prefers-reduced-motion` disables the CSS cursor animation.

## Page rationale

### Homepage

Acts as a running technical overview. It shows the web runtime before claims and places code beside output.

### Documentation

Uses the Fumadocs information architecture for long-form reading while inheriting Cinder colors, indexed navigation, straight borders, and terminal metadata.

### Examples

Uses a searchable ledger generated from repository Dart files. Compatibility is a first-class status: web, adapter, or native source.

### Example detail

Presents the real runner, exact source, repository path, controls, and browser limitation together. Restart destroys and recreates the isolated runtime route.

## Mobile decisions

- the command bar becomes horizontally scrollable;
- the three-column hero becomes one column;
- the source and runtime panes stack;
- the pipeline becomes a vertical sequence;
- example cells reduce to two columns, then one when required;
- shortcut hints collapse to repository and runtime status;
- terminals never force the document wider than the viewport.

## Accessibility decisions

- semantic headings and landmarks;
- global skip link;
- visible keyboard focus;
- iframe titles;
- text labels accompany status colors;
- controls are real buttons and links;
- reduced-motion support;
- native-only failures use explanatory text rather than color alone.

## Prohibited AI-slop patterns

- giant gradient slogan;
- three identical feature cards;
- glowing blob background;
- floating fake terminal screenshot;
- fabricated metrics or stars;
- invented testimonials;
- decorative particles;
- rounded-card grid for every sentence;
- HTML recreation of a Cinder TUI;
- claims that a sandbox is native SSH, PTY, process, filesystem, or FFmpeg access.

## Review gate

Before merging:

- capture desktop, tablet, and mobile screenshots;
- verify keyboard-only navigation;
- verify live runner boot, input, resize, and restart;
- inspect loading, compilation failure, and native-only states;
- run accessibility checks;
- compare every claim with the repository or generated manifest;
- reject any section that could be pasted onto an unrelated developer-tool landing page.
