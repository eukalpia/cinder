import Link from 'next/link';
import { CopyCommand } from '@/components/copy-command';
import { DartCode } from '@/components/dart-code';
import { SiteHeader } from '@/components/site-header';
import {
  cinderVersion,
  documentationCount,
  examples,
  runnableExamples,
} from '@/lib/examples';
import { withBasePath } from '@/lib/site';

const showcaseSource = `import 'package:cinder/cinder.dart';

void main() => runApp(const DashboardApp());

class DashboardApp extends CinderApp {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Cinder(
      title: 'Cinder Dashboard',
      theme: const CinderTheme(
        primary: Color(0xFFFFA235),
        accent: Color(0xFFFF8A3D),
      ),
      home: const Dashboard(),
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
  '60 FPS target',
  'Minimal diff updates',
  'Cross-platform consistent',
  'Keyboard & mouse events',
  'TrueColor & Unicode ready',
] as const;

const realWorld = [
  'Runs in any terminal (xterm, iTerm2, Windows Terminal, ...)',
  'Web runtime with WebSockets + Canvas fallback',
  'Handles resize, scrollback, and lost connections',
  'Battle-tested in production',
] as const;

const previewKinds = ['dashboard', 'editor', 'files', 'monitor', 'chat', 'table'] as const;

export default function HomePage() {
  const featured =
    runnableExamples.find((example) => example.slug === 'web-showcase') ??
    runnableExamples[0];
  const visibleExamples = examples.slice(0, 6);

  return (
    <main className="tui-page tui-page--control-room">
      <div className="tui-frame tui-frame--control-room">
        <SiteHeader />

        <section className="control-hero" aria-labelledby="hero-title">
          <article className="tui-panel control-intro">
            <h1 id="hero-title">
              Build terminal UIs
              <br />
              the Flutter way.<span className="tui-cursor">_</span>
            </h1>
            <p>
              Cinder is a Flutter-inspired framework for building fast, reactive, and
              beautiful terminal applications that run everywhere.
            </p>
            <ul>
              <li>Same declarative model you know</li>
              <li>Runs in any terminal or the browser</li>
              <li>Real-time updates at 60 FPS</li>
              <li>Tiny runtime. Zero config.</li>
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

          <section className="tui-panel control-scene" aria-label="Live Cinder city scene">
            <div className="control-scene-title">CINDER RENDER PIPELINE</div>
            {featured ? (
              <iframe
                title={`${featured.title} rendered by Cinder`}
                src={withBasePath(`/play/${featured.slug}/`)}
                className="control-scene-frame"
                loading="eager"
              />
            ) : (
              <pre className="control-scene-fallback">Cinder runtime is building…</pre>
            )}
            <span className="scene-tag scene-tag--state">STATE<br />▣▣▣</span>
            <span className="scene-tag scene-tag--diff">DIFF<br />▣▣▣</span>
            <span className="scene-tag scene-tag--events">EVENTS</span>
            <span className="scene-tag scene-tag--frame">FRAME&nbsp; 16.7ms</span>
          </section>

          <aside className="control-side">
            <section className="tui-panel control-code-panel">
              <header><span>● main.dart</span><span>DART</span></header>
              <DartCode code={showcaseSource} className="control-code" />
            </section>

            <section className="tui-panel control-dashboard">
              <header><span>› LIVE RUN (WEB)</span><strong>60 FPS</strong></header>
              <div className="dashboard-body">
                <nav>
                  <b>Cinder Dashboard</b>
                  <span className="is-active">◉ Overview</span>
                  <span>◎ Widgets&nbsp;&nbsp;&nbsp;128</span>
                  <span>◎ Events&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;842</span>
                  <span>◎ Performance</span>
                  <span>◎ Logs</span>
                  <span>◎ Settings</span>
                </nav>
                <div className="dashboard-main">
                  <label>ACTIVE USERS (24H)</label>
                  <pre aria-hidden="true">▁▂▃▅▃▆▄▂▇▅▄▆▃▅▇▆▄▅▇▃▆▄▅▇</pre>
                  <div className="dashboard-stats">
                    <span><b>FPS</b><em>60</em></span>
                    <span><b>EVENTS</b><em>842</em></span>
                    <span><b>DIFFS</b><em>128</em></span>
                    <span><b>LATENCY</b><em>2.1ms</em></span>
                  </div>
                </div>
              </div>
              <footer><span>● Connected to web runtime</span><span>{cinderVersion}</span><span>16.7ms/frame</span></footer>
            </section>
          </aside>
        </section>

        <section className="control-pipeline" aria-label="The Cinder pipeline">
          <h2>THE CINDER PIPELINE</h2>
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

        <section className="control-ledgers">
          <article className="tui-panel"><h2>RUNTIME GUARANTEES</h2><ul>{guarantees.map((item) => <li key={item}>✓ {item}</li>)}</ul></article>
          <article className="tui-panel"><h2>BUILT FOR THE REAL WORLD</h2><ul>{realWorld.map((item) => <li key={item}>› {item}</li>)}</ul></article>
          <article className="tui-panel control-install-panel">
            <h2>INSTALL</h2>
            <label>Dart / Flutter</label><code>$ dart pub add cinder</code>
            <label>Flutter (coming soon)</label><code>$ flutter pub add cinder</code>
          </article>
          <article className="tui-panel control-numbers">
            <h2>BY THE NUMBERS</h2>
            <div><dl><dt>~12KB</dt><dd>Runtime (minified)</dd><dt>0</dt><dd>Native deps</dd><dt>∞</dt><dd>Possibilities</dd></dl><pre aria-hidden="true">   ░\n  ▒▓▒\n ▓███▓\n▒█████▒\n ▓███▓\n  ▒▓▒</pre></div>
          </article>
        </section>

        <section className="control-bottom">
          <article className="tui-panel control-examples">
            <header><span>EXAMPLES</span><Link href="/examples">+ more</Link></header>
            <div>
              {visibleExamples.map((example, index) => (
                <Link href={`/examples/${example.slug}`} key={example.slug}>
                  <MiniPreview kind={previewKinds[index] ?? 'dashboard'} />
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

function MiniPreview({ kind }: { kind: (typeof previewKinds)[number] }) {
  const content = {
    dashboard: '▁▃▆▂  ┌────┐\n▂▅▇▃  │ 60 │\n─────  └────┘',
    editor: '1 import cinder\n2 class App {\n3   build() {}\n4 }',
    files: '▾ lib/\n  ├ app.dart\n  ├ ui.dart\n  └ theme.dart',
    monitor: 'CPU  ▂▄▆▃▇▅\nMEM  ▃▅▇▄▆▃\nNET  ▁▂▅▇▃▂',
    chat: '┌ message ──┐\n│ hello!    │\n└───────────┘\n> reply_',
    table: 'ID │ NAME │ FPS\n01 │ Web  │ 60\n02 │ TUI  │ 60',
  }[kind];
  return <pre aria-hidden="true">{content}</pre>;
}
