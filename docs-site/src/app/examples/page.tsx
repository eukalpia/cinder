import type { Metadata } from 'next';
import { ExampleDeck } from '@/components/example-deck';
import { SiteHeader } from '@/components/site-header';
import { examples, runnableExamples } from '@/lib/examples';

export const metadata: Metadata = {
  title: 'Examples',
  description:
    'Every Cinder example indexed from the repository, with live browser runners where the Dart source supports the web platform.',
};

export default function ExamplesPage() {
  return (
    <main className="marketing-page examples-page">
      <div className="marketing-shell">
        <SiteHeader />
        <header className="page-intro">
          <p className="kicker">Generated from the repository</p>
          <h1>Every example has an address.</h1>
          <p>
            Browser-compatible Dart sources are compiled into isolated live
            terminals. Native-only examples still get a stable page, source, and a
            precise reason they cannot run in a browser. No animated cardboard
            cut-outs pretending to be software.
          </p>
          <dl className="page-intro__facts">
            <div>
              <dt>Indexed</dt>
              <dd>{examples.length}</dd>
            </div>
            <div>
              <dt>Live web</dt>
              <dd>{runnableExamples.length}</dd>
            </div>
            <div>
              <dt>Source-only</dt>
              <dd>{examples.length - runnableExamples.length}</dd>
            </div>
          </dl>
        </header>
        <ExampleDeck examples={examples} />
        <footer className="site-footer">
          <span>Catalogue rebuilt on every Pages deployment.</span>
          <span>Source of truth: example/ and packages/*/example/</span>
        </footer>
      </div>
    </main>
  );
}
