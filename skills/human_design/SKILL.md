# Human Design

Use this skill for public interfaces, documentation sites, dashboards, examples, and developer tooling where the result must feel intentionally designed rather than assembled from generic SaaS patterns.

## Purpose

Create interfaces whose structure follows the product, the task, and the evidence available in the repository. The interface should still feel specific when the logo is removed.

## Before coding

Write down:

1. the primary user and their main task;
2. the page's information hierarchy;
3. the real product artifact shown first;
4. the visual thesis in one sentence;
5. technical and accessibility constraints;
6. mobile behavior;
7. patterns deliberately excluded as AI slop.

Do not start from a component gallery.

## Content rules

Use real code, real runtime output, real examples, generated counts, source links, test results, architecture, and honest limitations.

Never invent:

- user testimonials;
- GitHub stars or download counts;
- benchmarks;
- compatibility claims;
- example totals;
- logos or integrations;
- production adoption.

Every important claim needs evidence such as source code, a live runtime, a test, a benchmark, a document, or a repository link.

## Layout rules

Avoid automatic use of:

- centered marketing heroes;
- repeated three-card grids;
- rounded-card soup;
- giant gradient headings;
- decorative blobs and particles;
- floating dashboard mockups;
- alternating feature sections;
- meaningless whitespace;
- glassmorphism;
- fake terminal windows.

Prefer structures that fit the information:

- ledgers;
- editorial grids;
- split code/runtime views;
- tables;
- pipelines;
- terminal frames;
- direct application surfaces;
- dense but readable reference layouts.

A card is allowed only when the content is an independent object.

## Visual system

Define and document:

- background and no more than three surface levels;
- border hierarchy;
- one primary accent and one secondary accent;
- display, body, code, and metadata typography roles;
- spacing rhythm;
- hover, focus, active, selected, disabled, loading, error, and empty states.

Do not make all text monospace merely to look technical. Body text must remain readable. Use monospace for code, metadata, navigation indices, and runtime state.

## Motion

Motion must explain state, progress, focus, input, or a runtime transition. Do not animate decoration for its own sake. Respect `prefers-reduced-motion`.

## Copy

Write like an engineer documenting a real system:

- specific;
- calm;
- concise;
- honest;
- evidence-backed.

Remove vague words such as “revolutionary”, “next-generation”, “seamless”, “unlock”, “effortless”, and “powerful” unless the following sentence proves the claim.

## Accessibility

Require:

- semantic HTML;
- keyboard navigation;
- visible focus;
- useful labels;
- no color-only meaning;
- sufficient contrast;
- 200% zoom support;
- 320px responsive support;
- reduced-motion behavior;
- real loading, error, empty, offline, and native-only states.

## Review sizes

Review screenshots at:

- 1440×1000;
- 1024×768;
- 768×1024;
- 390×844;
- 320×700.

## Human design review

Before completion ask:

- Could this page belong to any SaaS product?
- Does the design still identify the product without the logo?
- Is the real product shown before marketing copy?
- Does every section add new information?
- Are there repeated cards that should be rows, tables, or direct composition?
- Is any metric, screenshot, testimonial, or capability fake?
- Is any visual effect present without a functional reason?
- Does the interface work without a mouse?
- Are limitations visible where decisions are made?

If the result looks generic, redesign the composition rather than adding more decoration.

## Cinder-specific contract

For Cinder interfaces:

- show real Cinder Dart source;
- run real Cinder examples through `WebBackend`;
- use xterm.js only as the browser terminal host;
- never reproduce a Cinder application with React divs;
- use terminal cells, ASCII/Unicode scenes, borders, ledgers, and shortcut bars as functional structure;
- use ember/orange as the functional accent and violet as a restrained identity accent;
- never reuse Nocterm branding;
- generate example and documentation counts from the repository;
- state whether an example is direct web, adapter-backed, or native-only;
- never present a deterministic sandbox as real SSH, PTY, FFmpeg, filesystem, or process access;
- favor technical documentation over marketing copy.

## Completion gate

Do not declare completion while any of these remain:

- placeholder content;
- fake data;
- missing mobile review;
- missing keyboard test;
- missing loading/error/empty states;
- critical accessibility failures;
- generic AI landing-page composition;
- terminal UI simulated by decorative HTML when a real Cinder runtime is required.
