import { readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, ArrowUpRight, CircleAlert, Play } from 'lucide-react';
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
  const isAdapted = mode === 'browser-adapter' || mode === 'browser-sandbox';
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
        </div>

        <header className="example-hero">
          <div>
            <div className="example-hero__meta">
              <span>{example.category}</span>
              <span className={`compatibility compatibility--${mode}`}>
                {runtimeModeLabel(mode)}
              </span>
            </div>
            <h1>{example.title}</h1>
            <p>{example.description}</p>
            <p className="runtime-contract">{example.runtimeNote}</p>
          </div>
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
        </header>

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
                <h2 id="runtime-title">Run it here</h2>
              </div>
              <span>
                <Play size={14} /> isolated browser document
              </span>
            </div>
            {isAdapted ? (
              <div className="runtime-disclosure">
                <strong>{runtimeModeLabel(mode)}.</strong>{' '}
                {runtimeModeDescription(mode)}
              </div>
            ) : null}
            <iframe
              title={`${example.title} live Cinder terminal`}
              src={withBasePath(`/play/${example.slug}/`)}
              className="example-runtime__frame"
              loading="eager"
            />
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
                The original source remains indexed below. A future adapter can make
                this route interactive without changing its URL or pretending that a
                browser has native access.
              </p>
            </div>
          </section>
        )}

        {example.controls.length > 0 ? (
          <section className="example-controls" aria-labelledby="controls-title">
            <div>
              <p className="kicker">Interaction contract</p>
              <h2 id="controls-title">Controls</h2>
            </div>
            <ul>
              {example.controls.map((control) => (
                <li key={control}>{control}</li>
              ))}
            </ul>
          </section>
        ) : null}

        <section className="source-reader" aria-labelledby="source-title">
          <header>
            <div>
              <p className="kicker">Repository source</p>
              <h2 id="source-title">{example.repositoryPath}</h2>
            </div>
            <a href={example.sourceUrl}>
              Open on GitHub <ArrowUpRight size={14} />
            </a>
          </header>
          <pre>
            <code>{source}</code>
          </pre>
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
