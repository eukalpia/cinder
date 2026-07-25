import Link from 'next/link';
import { CopyCommand } from '@/components/copy-command';
import { DartCode } from '@/components/dart-code';
import { ExamplePreview } from '@/components/example-preview';
import { InteractiveCityLauncher } from '@/components/interactive-city-launcher';
import { SiteHeader } from '@/components/site-header';
import {
  cinderVersion,
  documentationCount,
  examples,
  runnableExamples,
} from '@/lib/examples';
import { withBasePath } from '@/lib/site';

const showcaseSource = `import 'dart:async';
import 'package:cinder/cinder.dart';

void main() {
  runApp(const CinderApp(child: WebShowcase()));
}

class WebShowcase extends StatefulWidget {
  const WebShowcase({super.key});

  @override
  State<WebShowcase> createState() => _WebShowcaseState();
}

class _WebShowcaseState extends State<WebShowcase> {
  Timer? ticker;
  int tick = 0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final world = ElectricCityPainter(
            width: constraints.maxWidth.floor(),
            height: constraints.maxHeight.floor(),
            tick: tick,
          ).paint();

          return Stack(children: world.layers);
        },
      ),
    );
  }
}`;

const pipelineStages = [
  ['◉', 'WIDGET', 'Describe UI\nimmutably'],
  ['⌘', 'ELEMENT', 'Build the\nelement tree'],
  ['◇', 'RENDER OBJECT', 'Layout & paint\nterminal cells'],
  ['▣', 'BUFFER', '2D cell buffer\n(width × height)'],
  ['✓', 'DIFF', 'Compute minimal\ncell changes'],
  ['▤', 'WEB BACKEND', 'Stream updates\nto the terminal'],
] as const;

const guarantees = [
  'Deterministic rendering',
  'Responsive terminal layout',
  'Minimal diff updates',
  'Cross-platform consistent',
  'Keyboard & mouse events',
  'TrueColor & Unicode ready',
] as const;

const realWorld = [
  'Runs in xterm, iTerm2, Windows Terminal, Kitty, and WezTerm',
  'The electric city is a real Cinder application hosted through xterm.js',
  'Handles resize, focus, pointer events, keyboard input, and teardown',
  'Generated examples are compiled from repository Dart source',
] as const;

export default function HomePage() {
  const featured =
    runnableExamples.find((example) => example.slug === 'web-showcase') ??
    runnableExamples[0];
  const visibleExamples = pickDiverseExamples(6);

  return (
    <main className="tui-page tui-page--control-room">
      <div className="tui-frame tui-frame--control-room">
        <SiteHeader />

        <section className="control-hero" aria-labelledby="hero-title">
          <article className="tui-panel control-intro">
            <p className="control-intro__eyebrow">REAL CINDER WEB RUNTIME</p>
            <h1 id="hero-title">
              Build terminal UIs
              <br />
              the Flutter way.<span className="tui-cursor">_</span>
            </h1>
            <p>
              Cinder is a Flutter-inspired framework for building fast, reactive,
              and beautiful terminal applications that run everywhere.
            </p>
            <ul>
              <li>Same declarative model you know</li>
              <li>Runs in any terminal or the browser</li>
              <li>Real frame scheduling, layout, paint, damage, and diff</li>
              <li>The world above is compiled Dart, not a screenshot</li>
            </ul>
            <div className="control-install">
              <strong>› INSTALL</strong>
              <div>
                <code>$ dart pub add cinder</code>
                <CopyCommand value="dart pub add cinder" />
              </div>
            </div>
            <small>Supports Dart 3.5+ · Web · macOS · Linux · Windows</small>
          </article>

          <section
            className="tui-panel control-scene control-scene--living"
            aria-label="Living Cinder electric city"
          >
            <iframe
              title="Living Cinder electric city"
              src={withBasePath('/city/web-showcase/')}
              className="control-scene-frame"
              loading="eager"
            />
          </section>

          <aside className="control-side">
            <section className="tui-panel control-code-panel">
              <header><span>● web_showcase.dart</span><span>DART</span></header>
              <DartCode code={showcaseSource} className="control-code" lineNumbers />
            </section>

            <section className="tui-panel control-dashboard">
              <header><span>› RUNTIME TELEMETRY</span><strong>CONNECTED</strong></header>
              <div className="dashboard-body">
                <nav>
                  <b>Electric City</b>
                  <span className="is-active">◉ World</span>
                  <span>◎ Cable arcs</span>
                  <span>◎ Plasma core</span>
                  <span>◎ Traffic flow</span>
                  <span>◎ Responsive</span>
                  <span>◎ WebBackend</span>
                </nav>
                <div className="dashboard-main">
                  <label>ENERGY FLOW</label>
                  <pre aria-hidden="true">▁▃▆█▅▂▇▄▁▆█▃▅▇▂▄█▆▃▇▅▁▆█</pre>
                  <div className="dashboard-stats">
                    <span><b>INPUT</b><em>2-WAY</em></span>
                    <span><b>EXAMPLES</b><em>{examples.length}</em></span>
                    <span><b>DOCS</b><em>{documentationCount}</em></span>
                    <span><b>BACKEND</b><em>WEB</em></span>
                  </div>
                </div>
              </div>
              <footer>
                <span>● Living Cinder runtime</span>
                <span>{cinderVersion}</span>
                <span>keyboard + mouse</span>
              </footer>
            </section>
          </aside>
        </section>

        <section className="control-pipeline" aria-label="The Cinder pipeline">
          <h2>CINDER RENDER PIPELINE</h2>
          <div>
            {pipelineStages.map(([icon, title, description], index) => (
              <article key={title}>
                <span>{icon}</span>
                <p><b>{title}</b><small>{description}</small></p>
                {index < pipelineStages.length - 1 ? <i>→</i> : null}
              </article>
            ))}
          </div>
        </section>

        {featured ? (
          <section className="control-live-runtime" aria-label="Interactive Cinder web runtime">
            <article className="tui-panel control-live-runtime__meta">
              <p className="kicker">REAL CINDER APPLICATION</p>
              <h2>The world is the runtime.</h2>
              <p>
                Electricity moves through the cable network, arcs jump between
                conductors, plasma climbs from the core, traffic crosses the districts,
                windows flicker, and the whole world recomposes whenever the terminal
                changes size.
              </p>
              <div className="control-live-runtime__facts">
                <span>Source <b>{featured.repositoryPath}</b></span>
                <span>Mode <b>{featured.runtimeMode}</b></span>
                <span>Runtime <b>continuous</b></span>
                <span>Backend <b>WebBackend</b></span>
                <span>Energy <b>↑ / ↓</b></span>
                <span>Phase <b>← / →</b></span>
                <span>Surge <b>E / Enter / click</b></span>
                <span>Pause <b>Space</b></span>
              </div>
            </article>
            <div className="control-live-runtime__frame">
              <InteractiveCityLauncher
                src={withBasePath(`/play/${featured.slug}/`)}
                fullScreenHref={`/play/${featured.slug}`}
              />
            </div>
          </section>
        ) : null}

        <section className="control-ledgers">
          <article className="tui-panel">
            <h2>RUNTIME GUARANTEES</h2>
            <ul>{guarantees.map((item) => <li key={item}>✓ {item}</li>)}</ul>
          </article>
          <article className="tui-panel">
            <h2>BUILT FOR THE REAL WORLD</h2>
            <ul>{realWorld.map((item) => <li key={item}>› {item}</li>)}</ul>
          </article>
          <article className="tui-panel control-install-panel">
            <h2>INSTALL</h2>
            <label>Dart</label><code>$ dart pub add cinder</code>
            <label>Run the city</label><code>$ dart run example/web_showcase.dart</code>
          </article>
          <article className="tui-panel control-numbers">
            <h2>BY THE NUMBERS</h2>
            <div>
              <dl>
                <dt>{examples.length}</dt><dd>Examples indexed</dd>
                <dt>{runnableExamples.length}</dt><dd>Browser runners</dd>
                <dt>{documentationCount}</dt><dd>Reference docs</dd>
              </dl>
              <pre aria-hidden="true">   ░{'\n'}  ▒▓▒{'\n'} ▓███▓{'\n'}▒█████▒{'\n'} ▓███▓{'\n'}  ▒▓▒</pre>
            </div>
          </article>
        </section>

        <section className="control-bottom">
          <article className="tui-panel control-examples">
            <header><span>EXAMPLES</span><Link href="/examples">+ all {examples.length}</Link></header>
            <div>
              {visibleExamples.map((example) => (
                <Link href={`/examples/${example.slug}`} key={example.slug}>
                  <ExamplePreview example={example} compact />
                  <strong>{example.title}</strong>
                </Link>
              ))}
            </div>
          </article>
          <article className="tui-panel control-docs">
            <header>DOCS &amp; REFERENCE</header>
            <div>
              <nav>
                <Link href="/docs">Getting Started <span>[..]</span></Link>
                <Link href="/docs/fundamentals/components">Concepts <span>[..]</span></Link>
                <Link href="/docs/examples">Guides <span>[..]</span></Link>
                <Link href="/docs/fundamentals/theming">Theming <span>[..]</span></Link>
                <Link href="/docs/interactivity/keyboard">Input &amp; Events <span>[..]</span></Link>
              </nav>
              <nav>
                <Link href="/api">API Reference <span>[..]</span></Link>
                <Link href="/docs/reference">CinderApp <span>[..]</span></Link>
                <Link href="/docs/reference">Widget Catalog <span>[..]</span></Link>
                <Link href="/docs/reference/renderer-v2">Rendering <span>[..]</span></Link>
                <Link href="/docs/web-runtime">Web Backend <span>[..]</span></Link>
              </nav>
            </div>
          </article>
        </section>

        <footer className="control-status">
          <span>? HELP</span><span>q QUIT</span><span>←→ NAVIGATE</span><span>j/k SCROLL</span><span>g TOP</span><span>G BOTTOM</span>
          <a href="https://github.com/eukalpia/cinder">GITHUB.COM/EUKALPIA/CINDER</a>
          <strong>WEB RUNTIME: ONLINE</strong>
        </footer>
      </div>
    </main>
  );
}

function pickDiverseExamples(limit: number) {
  const selected = [] as typeof examples;
  const categories = new Set<string>();

  for (const example of examples) {
    if (!categories.has(example.category)) {
      selected.push(example);
      categories.add(example.category);
    }
    if (selected.length === limit) return selected;
  }

  for (const example of examples) {
    if (!selected.some((item) => item.slug === example.slug)) selected.push(example);
    if (selected.length === limit) break;
  }
  return selected;
}
