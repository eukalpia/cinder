# Legacy landing sources

`docs-site/` is the only public Cinder website and the source of the GitHub Pages deployment.

This directory remains temporarily because `landing/demos/` contains historical browser-demo Dart sources that are still included in the generated example catalogue. It must not gain a second homepage, independent navigation, duplicated documentation, or separate deployment workflow.

When migrating code from this directory:

- move reusable runtime integration into `docs-site/` or the Cinder web backend;
- preserve original demo source paths while catalogue links depend on them;
- remove CDN and manually maintained bundle logic;
- do not edit generated files to make examples appear compatible;
- delete this directory once all useful demo sources have canonical homes.
