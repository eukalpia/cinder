import Link from 'next/link';
import { CopyCommand } from '@/components/copy-command';
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
  runApp(const CinderApp(
    child: WebShowcase(),
  ));
}

class WebShowcase extends StatefulWidget {
  const WebShowcase({super.key});

  @override
  State<WebShowcase> createState() => _WebShowcaseState();
}

class _WebShowcaseState extends State<WebShowcase> {
  int frame = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('CINDER RENDER PIPELINE'),
        Expanded(child: Text(cityFrames[frame])),
        Text('Widget → Element → RenderObject → Diff'),
      ],
    );
  }
}`;

const pipelineStages = [
  ['01', 'WIDGET', 'Describe UI immutably'],
  ['02', 'ELEMENT', 'Preserve identity and state'],
  ['03', 'RENDER OBJECT', 'Layout and paint cells'],
  ['04', 'BUFFER', 'Own graphemes and styles'],
  ['05', 'DIFF', 'Emit minimal terminal updates'],
  ['06', 'WEB BACKEND', 'Bridge output to xterm.js'],
] as const;

const guarantees = [
  'Deterministic Widget → Element → RenderObject pipeline',
  'Reusable cell buffers and differential terminal output',
  'Keyboard, mouse, focus, resize, and Unicode support',
  'Native terminal and isolated browser runtime',
  'No React reimplementation of the terminal renderer',
] as const;

const runtimeNotes = [
  'Dart source is compiled during the site build.',
  'Every application runs in a fresh iframe context.',
  'xterm.js is only a terminal host; Cinder paints the UI.',
  'Native-only capabilities are labelled instead of faked.',
] as const;

export default function HomePage() {
  const featured =
    runnableExamples.find((example) => example.slug === 'web-showcase') ??
    runnableExamples.find((example) => example.category === 'Motion') ??
    runnableExamples[0];
  const visibleExamples = examples.slice(0, 6);

  return (
    <main className="tui-page">
      <div className="tui-frame">
        <SiteHeader />

        <section className="tui-hero" aria-labelledby="hero-title">
          <article className="tui-panel tui-intro">
            <p className="tui-eyebrow">CINDER / DART TERMINAL UI FRAMEWORK</p>
            <h1 id="hero-title">
              Build terminal UIs
              <br />
              the Flutter way.<span className="tui-cursor">_</span>
            </h1>
            <p className="tui-copy">
              Cinder brings Widget, Element, State, BuildContext, and RenderObject
              architecture to terminal applications without shipping Flutter or a
              browser UI clone.
            </p>

            <ul className="tui-list" aria-label="Cinder capabilities">
              <li>Same declarative model on native terminals and the browser</li>
              <li>Real frame scheduling, layout, paint, damage, and diff</li>
              <li>Interactive examples compiled from repository Dart source</li>
              <li>Static documentation and GitHub Pages deployment</li>
            </ul>

            <div className="tui-install" aria-label="Install Cinder">
              <span className="tui-panel-label">INSTALL</span>
              <code>$ dart pub add cinder</code>
              <CopyCommand value="dart pub add cinder" />
            </div>

            <div className="tui-platforms">
              Dart 3.5+ · Web · macOS · Linux · Windows
            </div>
          </article>

          <section className="tui-panel tui-scene" aria-label="Live Cinder scene">
            <header className="tui-panel-bar">
              <span>CINDER RENDER PIPELINE</span>
              <span className="tui-live">● LIVE DART</span>
            </header>
            {featured ? (
              <iframe
                title={`${featured.title} rendered by Cinder`}
                src={withBasePath(`/play/${featured.slug}/`)}
                className="tui-scene-frame"
                loading="eager"
              />
            ) : (
              <pre className="tui-scene-fallback">
                <code>{`                 STATE           DIFF
                   │               │
          ┌────────┴───────────────┴────────┐
          │     CINDER WEB RUNTIME          │
          │  waiting for generated bundle  │
          └─────────────────────────────────┘

 Widget → Element → RenderObject → Buffer → Diff`}</code>
              </pre>
            )}
            <footer className="tui-panel-foot">
              <span>EVENTS: keyboard / mouse / resize</span>
              <span>FRAME: renderer-owned</span>
            </footer>
          </section>

          <aside className="tui-hero-side">
            <section className="tui-panel tui-source-panel">
              <header className="tui-panel-bar">
                <span>● main.dart</span>
                <span>DART</span>
              </header>
              <pre className="tui-code">
                <code>{showcaseSource}</code>
              </pre>
            </section>

            <section className="tui-panel tui-runtime-panel">
              <header className="tui-panel-bar">
                <span>LIVE RUN / WEB</span>
                <span className="tui-fps">60 FPS TARGET</span>
              </header>
              <div className="tui-runtime-grid">
                <nav aria-label="Runtime sections">
                  <strong>Cinder Runtime</strong>
                  <span className="is-active">› Overview</span>
                  <span>  Widgets</span>
                  <span>  Events</span>
                  <span>  Performance</span>
                  <span>  Logs</span>
                </nav>
                <div className="tui-signal" aria-hidden="true">
                  <span>FRAME ACTIVITY</span>
                  <pre>{`▁▂▃▂▄▆▅▃▅▇▆▄▃▅▆▇▅▄▆▇▆▅▄▃`}</pre>
                </div>
                <dl>
                  <div>
                    <dt>EXAMPLES</dt>
                    <dd>{examples.length || 'build'}</dd>
                  </div>
                  <div>
                    <dt>WEB</dt>
                    <dd>{runnableExamples.length || 'scan'}</dd>
                  </div>
                  <div>
                    <dt>DOCS</dt>
                    <dd>{documentationCount || 'sync'}</dd>
                  </div>
                  <div>
                    <dt>VERSION</dt>
                    <dd>{cinderVersion}</dd>
                  </div>
                </dl>
              </div>
              <footer className="tui-panel-foot tui-connected">
                <span>● Connected to web runtime</span>
                <span>isolated iframe</span>
              </footer>
            </section>
          </aside>
        </section>

        <section className="tui-pipeline" aria-labelledby="pipeline-title">
          <h2 id="pipeline-title" className="sr-only">
            Cinder rendering pipeline
          </h2>
          {pipelineStages.map(([number, title, description], index) => (
            <div className="tui-pipeline-stage" key={title}>
              <span>{number}</span>
              <strong>{title}</strong>
              <small>{description}</small>
              {index < pipelineStages.length - 1 ? (
                <b aria-hidden="true">→</b>
              ) : null}
            </div>
          ))}
        </section>

        <section className="tui-ledger-grid">
          <article className="tui-panel tui-ledger">
            <h2>RUNTIME GUARANTEES</h2>
            <ul>
              {guarantees.map((guarantee) => (
                <li key={guarantee}>✓ {guarantee}</li>
              ))}
            </ul>
          </article>

          <article className="tui-panel tui-ledger">
            <h2>THE WEB RUNTIME IS REAL</h2>
            <ul>
              {runtimeNotes.map((note) => (
                <li key={note}>› {note}</li>
              ))}
            </ul>
            <Link href="/docs/web-runtime">Open runtime contract →</Link>
          </article>

          <article className="tui-panel tui-ledger tui-install-ledger">
            <h2>INSTALL</h2>
            <p>Dart package</p>
            <code>$ dart pub add cinder</code>
            <p>Repository development</p>
            <code>$ git clone github.com/eukalpia/cinder</code>
          </article>

          <article className="tui-panel tui-ledger tui-numbers">
            <h2>BUILD INDEX</h2>
            <dl>
              <div>
                <dt>{examples.length || '—'}</dt>
                <dd>repository examples</dd>
              </div>
              <div>
                <dt>{runnableExamples.length || '—'}</dt>
                <dd>browser-runnable</dd>
              </div>
              <div>
                <dt>{documentationCount || '—'}</dt>
                <dd>reference documents</dd>
              </div>
            </dl>
          </article>
        </section>

        <section className="tui-bottom-grid">
          <article className="tui-panel tui-examples-panel">
            <header className="tui-section-bar">
              <div>
                <span>EXAMPLES</span>
                <small>generated from repository source</small>
              </div>
              <Link href="/examples">+ open catalogue</Link>
            </header>
            <div className="tui-example-strip">
              {visibleExamples.map((example, index) => (
                <Link href={`/examples/${example.slug}`} key={example.slug}>
                  <span>{String(index + 1).padStart(2, '0')}</span>
                  <strong>{example.title}</strong>
                  <small>{example.category}</small>
                  <em>{example.runnable ? 'WEB' : 'NATIVE'}</em>
                </Link>
              ))}
              {visibleExamples.length === 0 ? (
                <p>Run `npm run prepare:site` to generate the example index.</p>
              ) : null}
            </div>
          </article>

          <article className="tui-panel tui-docs-panel">
            <header className="tui-section-bar">
              <div>
                <span>DOCS / REFERENCE</span>
                <small>source-backed documentation</small>
              </div>
            </header>
            <div className="tui-doc-columns">
              <nav aria-label="Documentation links">
                <Link href="/docs">Getting started <span>[..]</span></Link>
                <Link href="/docs/fundamentals/components">
                  Widget model <span>[..]</span>
                </Link>
                <Link href="/docs/interactivity/focus">
                  Input and focus <span>[..]</span>
                </Link>
                <Link href="/docs/testing/basics">Testing <span>[..]</span></Link>
              </nav>
              <nav aria-label="Reference links">
                <Link href="/docs/reference">Engineering reference <span>[..]</span></Link>
                <Link href="/docs/reference/renderer-v2">Renderer V2 <span>[..]</span></Link>
                <Link href="/docs/reference/images">Images <span>[..]</span></Link>
                <Link href="/docs/web-runtime">Web backend <span>[..]</span></Link>
              </nav>
            </div>
          </article>
        </section>

        <footer className="tui-statusbar">
          <span>[?] HELP</span>
          <span>[1–5] NAVIGATE</span>
          <span>[J/K] SCROLL</span>
          <span>[/] SEARCH</span>
          <a href="https://github.com/eukalpia/cinder">GITHUB.COM/EUKALPIA/CINDER</a>
          <strong>● WEB RUNTIME: ONLINE</strong>
        </footer>
      </div>
    </main>
  );
}
