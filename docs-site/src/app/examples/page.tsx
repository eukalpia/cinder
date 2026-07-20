import type { Metadata } from 'next';
import { ExampleDeck } from '@/components/example-deck';
import { SiteHeader } from '@/components/site-header';
import { examples } from '@/lib/examples';

export const metadata: Metadata = {
  title: 'Examples',
  description:
    'Every Cinder example indexed from the repository, with direct web builds, explicit browser adapters, deterministic sandboxes, and honest native boundaries.',
};

export default function ExamplesPage() {
  const direct = examples.filter((example) => example.runtimeMode === 'direct-web').length;
  const adapted = examples.filter(
    (example) =>
      example.runtimeMode === 'browser-adapter' ||
      example.runtimeMode === 'browser-sandbox',
  ).length;
  const native = examples.filter(
    (example) =>
      example.runtimeMode === 'native-only' || example.runtimeMode === 'build-failed',
  ).length;

  return (
    <main className="marketing-page examples-page">
      <div className="marketing-shell">
        <SiteHeader />
        <header className="page-intro">
          <p className="kicker">Generated from the repository</p>
          <h1>Every example has an address.</h1>
          <p>
            Original Dart sources run directly when the browser supports them.
            Capability-dependent examples use clearly labelled adapters or deterministic
            sandboxes. Native boundaries remain visible instead of being disguised as
            fake software.
          </p>
          <dl className="page-intro__facts">
            <div>
              <dt>Indexed</dt>
              <dd>{examples.length}</dd>
            </div>
            <div>
              <dt>Direct web</dt>
              <dd>{direct}</dd>
            </div>
            <div>
              <dt>Adapter / sandbox</dt>
              <dd>{adapted}</dd>
            </div>
            <div>
              <dt>Native / failed</dt>
              <dd>{native}</dd>
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
