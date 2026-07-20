import { readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, ArrowUpRight, CircleAlert, Maximize2, Play } from 'lucide-react';
import { DartCode } from '@/components/dart-code';
import { ExamplePreview } from '@/components/example-preview';
import { SiteHeader } from '@/components/site-header';
import {
  examples,
  getExample,
  runtimeModeDescription,
  runtimeModeLabel,
} from '@/lib/examples';
import { withBasePath } from '@/lib/site';

type ExamplePageProps = {
  params: Promise<{ slug: string }>;
};

export function generateStaticParams() {
  return examples.map((example) => ({ slug: example.slug }));
}

export async function generateMetadata({
  params,
}: ExamplePageProps): Promise<Metadata> {
  const { slug } = await params;
  const example = getExample(slug);
  if (!example) return {};
  return {
    title: example.title,
    description: example.description,
  };
}

export default async function ExamplePage({ params }: ExamplePageProps) {
  const { slug } = await params;
  const example = getExample(slug);
  if (!example) notFound();

  const source = await readExampleSource(example.repositoryPath);
  const mode = example.runtimeMode;
  const controls = example.controls ?? [];
  const isAdapted = mode === 'browser-adapter' || mode === 'browser-sandbox';
  const related = relatedExamples(example.slug, example.category);
  const boundaryTitle =
    mode === 'build-failed'
      ? 'The source is indexed, but this browser build failed.'
      : 'The browser runner stops at the real boundary.';

  return (
    <main className="marketing-page example-page">
      <div className="marketing-shell">
        <SiteHeader />
        <div className="example-breadcrumb">
          <Link href="/examples">
            <ArrowLeft size={14} /> Examples
          </Link>
          <span>/</span>
          <span>{example.category}</span>
          <span>/</span>
          <span>{example.slug}</span>
        </div>

        <section className="example-detail-hero">
          <article className="tui-panel example-detail-hero__copy">
            <div className="example-hero__meta">
              <span>{example.category}</span>
              <span className={`compatibility compatibility--${mode}`}>
                {runtimeModeLabel(mode)}
              </span>
            </div>
            <h1>{example.title}</h1>
            <p>{example.description}</p>
            <p className="runtime-contract">{example.runtimeNote}</p>
            <div className="example-source-actions">
              <a href={example.sourceUrl} className="button button--quiet">
                Original source <ArrowUpRight size={15} />
              </a>
              {example.adapterSourceUrl ? (
                <a href={example.adapterSourceUrl} className="button button--quiet">
                  Adapter source <ArrowUpRight size={15} />
                </a>
              ) : null}
            </div>
          </article>
          <article className="tui-panel example-detail-hero__preview">
            <ExamplePreview example={example} />
          </article>
        </section>

        <section className="example-detail-grid">
          <div>
            {example.runnable ? (
              <section className="example-runtime" aria-labelledby="runtime-title">
                <div className="example-runtime__heading">
                  <div>
                    <p className="kicker">
                      {mode === 'direct-web'
                        ? 'Compiled repository Dart'
                        : mode === 'browser-sandbox'
                          ? 'Deterministic Cinder sandbox'
                          : 'Cinder browser adapter'}
                    </p>
                    <h2 id="runtime-title">Interactive runtime</h2>
                  </div>
                  <Link
                    href={`/play/${example.slug}`}
                    className="example-runtime__fullscreen"
                  >
                    <Maximize2 size={13} /> Full screen
                  </Link>
                </div>
                {isAdapted ? (
                  <div className="runtime-disclosure">
                    <strong>{runtimeModeLabel(mode)}.</strong>{' '}
                    {runtimeModeDescription(mode)}
                  </div>
                ) : null}
                <div className="example-runtime__stage">
                  <div className="example-runtime__stage-bar">
                    <span>› {example.slug}.dart</span>
                    <b>● CINDER WEB LIVE</b>
                  </div>
                  <iframe
                    title={`${example.title} live Cinder terminal`}
                    src={withBasePath(`/play/${example.slug}/`)}
                    className="example-runtime__frame"
                    loading="eager"
                  />
                  <div className="example-runtime__stage-foot">
                    <span>{controls.length > 0 ? controls.join(' · ') : 'No special controls'}</span>
                    <span>Click the terminal before typing</span>
                  </div>
                </div>
                {controls.length > 0 ? (
                  <div className="example-runtime__controls" aria-label="Runtime controls">
                    {controls.map((control) => <span key={control}>{control}</span>)}
                  </div>
                ) : null}
              </section>
            ) : (
              <section className="native-notice" aria-labelledby="runtime-title">
                <CircleAlert size={20} />
                <div>
                  <p className="kicker">
                    {mode === 'build-failed'
                      ? 'Browser compilation failure'
                      : 'Native capability required'}
                  </p>
                  <h2 id="runtime-title">{boundaryTitle}</h2>
                  <p>{example.reason}</p>
                  <p>
                    The original source stays indexed below. The route never shows a
                    fake success state for a capability the browser cannot provide.
                  </p>
                </div>
              </section>
            )}
          </div>

          <aside className="example-detail-side">
            <section className="tui-panel example-fact-panel">
              <h2>INTERACTION CONTRACT</h2>
              <ul>
                {controls.length > 0 ? (
                  controls.map((control) => <li key={control}>› {control}</li>)
                ) : (
                  <li>› No special controls required</li>
                )}
              </ul>
            </section>
            <section className="tui-panel example-fact-panel">
              <h2>RUNTIME DETAILS</h2>
              <dl>
                <dt>Mode</dt><dd>{runtimeModeLabel(mode)}</dd>
                <dt>Category</dt><dd>{example.category}</dd>
                <dt>Runnable</dt><dd>{example.runnable ? 'yes' : 'no'}</dd>
                <dt>Bundle</dt><dd>{example.bundle ? 'generated' : 'none'}</dd>
              </dl>
            </section>
            <section className="tui-panel example-fact-panel">
              <h2>TAGS</h2>
              <ul>
                {(example.tags ?? []).map((tag) => <li key={tag}># {tag}</li>)}
              </ul>
            </section>
          </aside>
        </section>

        <section className="tui-panel example-source-reader" aria-labelledby="source-title">
          <header>
            <h2 id="source-title">● {example.repositoryPath}</h2>
            <a href={example.sourceUrl}>
              Open on GitHub <ArrowUpRight size={14} />
            </a>
          </header>
          <DartCode
            code={source}
            title={example.repositoryPath}
            lineNumbers
            className="tui-code tui-code--source"
          />
        </section>

        <section className="tui-panel example-related">
          <header>
            <span>RELATED EXAMPLES</span>
            <Link href="/examples">Browse all {examples.length}</Link>
          </header>
          <div className="example-related__grid">
            {related.map((item) => (
              <Link className="example-card" href={`/examples/${item.slug}`} key={item.slug}>
                <div className="example-card__preview">
                  <ExamplePreview example={item} compact />
                </div>
                <div className="example-card__content">
                  <div className="example-card__heading">
                    <strong>{item.title}</strong>
                    <span className={`compatibility compatibility--${item.runtimeMode}`}>
                      {runtimeModeLabel(item.runtimeMode)}
                    </span>
                  </div>
                  <p className="example-card__description">{item.description}</p>
                </div>
              </Link>
            ))}
          </div>
        </section>

        <footer className="site-footer">
          <span>Example route: /examples/{example.slug}</span>
          <span>{runtimeModeLabel(mode)}</span>
        </footer>
      </div>
    </main>
  );
}

async function readExampleSource(repositoryPath: string) {
  const repositoryRoot = path.resolve(process.cwd(), '..');
  try {
    return await readFile(path.join(repositoryRoot, repositoryPath), 'utf8');
  } catch {
    return '// Source is generated during the production build.\n';
  }
}

function relatedExamples(slug: string, category: string) {
  const related = examples.filter(
    (example) => example.slug !== slug && example.category === category,
  );
  const fallback = examples.filter(
    (example) => example.slug !== slug && !related.some((item) => item.slug === example.slug),
  );
  return [...related, ...fallback].slice(0, 3);
}
