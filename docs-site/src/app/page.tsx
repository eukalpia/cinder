import Link from 'next/link';
import { ArrowUpRight, Check, GitBranch, TerminalSquare } from 'lucide-react';
import { SiteHeader } from '@/components/site-header';
import {
  cinderVersion,
  documentationCount,
  examples,
  runnableExamples,
} from '@/lib/examples';
import { withBasePath } from '@/lib/site';

const counterSource = `class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space) {
          setState(() => count++);
          return true;
        }
        return false;
      },
      child: Center(child: Text('Count: $count')),
    );
  }
}`;

export default function HomePage() {
  const featured =
    runnableExamples.find((example) => example.category === 'Input') ??
    runnableExamples[0];
  const visibleExamples = examples.slice(0, 6);

  return (
    <main className="marketing-page">
      <div className="marketing-shell">
        <SiteHeader />

        <section className="hero" aria-labelledby="hero-title">
          <div className="hero__copy">
            <p className="kicker">Dart · terminal cells · real browser runtime</p>
            <h1 id="hero-title">
              Flutter&apos;s UI model,
              <br />
              rebuilt for terminals.
            </h1>
            <p className="hero__lede">
              Cinder is a Widget, Element, and RenderObject framework for terminal
              applications. The same application code now targets native terminals
              and an isolated browser terminal—without replacing the renderer with
              a decorative mockup.
            </p>
            <div className="hero__actions">
              <Link href="/docs/installation" className="button button--primary">
                Install Cinder <ArrowUpRight size={15} />
              </Link>
              <Link href="/examples" className="button button--quiet">
                Open example index
              </Link>
            </div>
            <dl className="hero__facts">
              <div>
                <dt>Release line</dt>
                <dd>{cinderVersion}</dd>
              </div>
              <div>
                <dt>Repository examples</dt>
                <dd>{examples.length || 'generated at build'}</dd>
              </div>
              <div>
                <dt>Reference documents</dt>
                <dd>{documentationCount || 'synced at build'}</dd>
              </div>
            </dl>
          </div>

          <div className="hero__runtime" aria-label="Live Cinder browser example">
            <div className="runtime-window">
              <div className="runtime-window__bar">
                <span className="runtime-window__title">
                  <TerminalSquare size={14} /> cinder web runner
                </span>
                <span className="runtime-window__status">
                  <i /> generated from Dart
                </span>
              </div>
              {featured ? (
                <iframe
                  title={`${featured.title} live Cinder example`}
                  src={withBasePath(`/play/${featured.slug}/`)}
                  className="runtime-window__frame"
                  loading="eager"
                />
              ) : (
                <pre className="runtime-window__fallback">
                  <code>
                    $ npm run build{`\n`}
                    → scan repository examples{`\n`}
                    → compile browser-safe Dart{`\n`}
                    → publish isolated runners
                  </code>
                </pre>
              )}
              <div className="runtime-window__foot">
                <span>{featured?.repositoryPath ?? 'example/**/*.dart'}</span>
                <span>keyboard · mouse · resize</span>
              </div>
            </div>
          </div>
        </section>

        <section className="proof-strip" aria-label="Runtime guarantees">
          <span>
            <Check size={14} /> real Cinder frame pipeline
          </span>
          <span>
            <Check size={14} /> one isolated iframe per app
          </span>
          <span>
            <Check size={14} /> static GitHub Pages export
          </span>
          <span>
            <Check size={14} /> native limitations disclosed, never simulated
          </span>
        </section>

        <section className="split-section" aria-labelledby="model-title">
          <div className="section-heading">
            <p className="kicker">Programming model</p>
            <h2 id="model-title">One widget tree. Two terminal backends.</h2>
            <p>
              Cinder does not turn a screenshot into a website. The browser runner
              hosts the actual Dart application and forwards terminal I/O through a
              narrow bridge.
            </p>
          </div>
          <div className="pipeline" role="list">
            {[
              ['01', 'Widget tree', 'Immutable configuration and stateful lifecycles.'],
              ['02', 'Element reconciliation', 'Persistent identity and scoped rebuilds.'],
              ['03', 'RenderObjects', 'Cell-aware layout, paint, damage, and diff.'],
              ['04', 'Backend', 'stdio on native; xterm bridge in the browser.'],
            ].map(([number, title, description]) => (
              <div className="pipeline__row" role="listitem" key={number}>
                <span>{number}</span>
                <strong>{title}</strong>
                <p>{description}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="code-section" aria-labelledby="code-title">
          <div className="code-section__source">
            <div className="code-caption">
              <span>counter.dart</span>
              <span>same source on native and web</span>
            </div>
            <pre>
              <code>{counterSource}</code>
            </pre>
          </div>
          <div className="code-section__notes">
            <p className="kicker">No compatibility theatre</p>
            <h2 id="code-title">The browser is another terminal host.</h2>
            <ul className="plain-checklist">
              <li>Input is forwarded as terminal byte sequences.</li>
              <li>Resize events update the Cinder terminal binding.</li>
              <li>ANSI output is rendered by xterm.js, not reimplemented in React.</li>
              <li>Each route owns a fresh JavaScript context, so apps actually stop.</li>
            </ul>
            <Link href="/docs/web-runtime" className="text-link">
              Read the web runtime contract <ArrowUpRight size={14} />
            </Link>
          </div>
        </section>

        <section className="example-preview" aria-labelledby="examples-title">
          <div className="section-heading section-heading--row">
            <div>
              <p className="kicker">Repository-indexed</p>
              <h2 id="examples-title">Examples are products, not thumbnails.</h2>
            </div>
            <Link href="/examples" className="text-link">
              Browse all examples <ArrowUpRight size={14} />
            </Link>
          </div>
          <div className="example-preview__ledger">
            {visibleExamples.map((example, index) => (
              <Link href={`/examples/${example.slug}`} key={example.slug}>
                <span>{String(index + 1).padStart(2, '0')}</span>
                <strong>{example.title}</strong>
                <small>{example.category}</small>
                <em className={example.runnable ? 'is-web' : 'is-native'}>
                  {example.runnable ? 'live web' : 'native source'}
                </em>
                <ArrowUpRight size={14} />
              </Link>
            ))}
            {visibleExamples.length === 0 ? (
              <div className="example-preview__empty">
                The catalogue is generated during the production build from
                <code> example/</code> and package example directories.
              </div>
            ) : null}
          </div>
        </section>

        <section className="docs-callout" aria-labelledby="docs-title">
          <div>
            <p className="kicker">Documentation without drift</p>
            <h2 id="docs-title">The engineering reference comes from the repo.</h2>
          </div>
          <p>
            Architecture, renderer, images, icons, security, and performance notes
            are copied from <code>doc/</code> during every build. The public docs
            cannot quietly become a different project from the source tree.
          </p>
          <Link href="/docs/reference" className="button button--primary">
            Open engineering reference
          </Link>
        </section>

        <footer className="site-footer">
          <span>
            <GitBranch size={14} /> eukalpia/cinder
          </span>
          <span>Apache-2.0 · built in Dart</span>
        </footer>
      </div>
    </main>
  );
}
