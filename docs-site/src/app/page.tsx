import Link from 'next/link';
import { CopyCommand } from '@/components/copy-command';
import { DartCode } from '@/components/dart-code';
import { ExamplePreview } from '@/components/example-preview';
import { SiteHeader } from '@/components/site-header';
import {
  cinderVersion,
  documentationCount,
  examples,
  runnableExamples,
} from '@/lib/examples';
import { withBasePath } from '@/lib/site';

const showcaseSource = `import 'package:cinder/cinder.dart';

void main() {
  runApp(const CinderApp(child: Dashboard()));
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double energy = 1.0;
  bool paused = false;

  @override
  Widget build(BuildContext context) {
    return ElectricCity(
      energy: energy,
      paused: paused,
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
  'Real Cinder application hosted through xterm.js',
  'Handles resize, focus, pointer events, keyboard input, and teardown',
  'Generated examples are compiled from repository Dart source',
] as const;

export default function HomePage() {
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
              <li>The city beside this panel is compiled Dart, not a screenshot</li>
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
            aria-label="Interactive isometric Cinder city"
          >
            <iframe
              title="Interactive isometric Cinder city"
              src={withBasePath('/city/web-showcase/')}
              className="control-scene-frame"
              loading="eager"
            />
          </section>

          <aside className="control-side">
            <section className="tui-panel control-code-panel">
              <header>
                <span>● main.dart</span>
                <span>DART</span>
              </header>
              <DartCode code={showcaseSource} className="control-code" lineNumbers />
            </section>

            <section className="tui-panel control-dashboard">
              <header>
                <span>› LIVE RUN (WEB)</span>
                <strong>60 FPS</strong>
              </header>
              <div className="dashboard-body">
                <nav>
                  <b>Cinder Dashboard</b>
                  <span className="is-active">◉ Overview</span>
                  <span>◎ Widgets</span>
                  <span>◎ Events</span>
                  <span>◎ Performance</span>
                  <span>◎ Logs</span>
                  <span>◎ Settings</span>
                </nav>
                <div className="dashboard-main">
                  <label>ACTIVE FRAMES</label>
                  <pre aria-hidden="true">▁▃▆█▅▂▇▄▁▆█▃▅▇▂▄█▆▃▇▅▁▆█</pre>
                  <div className="dashboard-stats">
                    <span>
                      <b>FPS</b>
                      <em>60</em>
                    </span>
                    <span>
                      <b>EVENTS</b>
                      <em>LIVE</em>
                    </span>
                    <span>
                      <b>DIFFS</b>
                      <em>MIN</em>
                    </span>
                    <span>
                      <b>LATENCY</b>
                      <em>LOW</em>
                    </span>
                  </div>
                </div>
              </div>
              <footer>
                <span>● Connected to web runtime</span>
                <span>{cinderVersion}</span>
                <span>pointer + animation</span>
              </footer>
            </section>
          </aside>
        </section>

        <section className="control-pipeline" aria-label="The Cinder pipeline">
          <h2>THE CINDER PIPELINE</h2>
          <div>
            {pipelineStages.map(([icon, title, description], index) => (
              <article key={title}>
                <span>{icon}</span>
                <p>
                  <b>{title}</b>
                  <small>{description}</small>
                </p>
                {index < pipelineStages.length - 1 ? <i>→</i> : null}
              </article>
            ))}
          </div>
        </section>

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
            <label>Dart</label>
            <code>$ dart pub add cinder</code>
            <label>Run an example</label>
            <code>$ dart run example/web_showcase.dart</code>
          </article>
          <article className="tui-panel control-numbers">
            <h2>BY THE NUMBERS</h2>
            <div>
              <dl>
                <dt>{examples.length}</dt>
                <dd>Examples indexed</dd>
                <dt>{runnableExamples.length}</dt>
                <dd>Browser runners</dd>
                <dt>{documentationCount}</dt>
                <dd>Reference docs</dd>
              </dl>
              <pre aria-hidden="true">   ░{`\n`}  ▒▓▒{`\n`} ▓███▓{`\n`}▒█████▒{`\n`} ▓███▓{`\n`}  ▒▓▒</pre>
            </div>
          </article>
        </section>

        <section className="control-bottom">
          <article className="tui-panel control-examples">
            <header>
              <span>EXAMPLES</span>
              <Link href="/examples">+ all {examples.length}</Link>
            </header>
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
          <span>? HELP</span>
          <span>q QUIT</span>
          <span>←→ NAVIGATE</span>
          <span>j/k SCROLL</span>
          <span>g TOP</span>
          <span>G BOTTOM</span>
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
