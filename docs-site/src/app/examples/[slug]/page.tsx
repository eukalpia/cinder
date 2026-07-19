import { readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ArrowLeft, ArrowUpRight, CircleAlert, Play } from 'lucide-react';
import { SiteHeader } from '@/components/site-header';
import { examples, getExample } from '@/lib/examples';
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
              <span
                className={`compatibility compatibility--${example.runnable ? 'web' : 'native'}`}
              >
                {example.runnable ? 'Live web' : 'Native source'}
              </span>
            </div>
            <h1>{example.title}</h1>
            <p>{example.description}</p>
          </div>
          <a href={example.sourceUrl} className="button button--quiet">
            View source <ArrowUpRight size={15} />
          </a>
        </header>

        {example.runnable ? (
          <section className="example-runtime" aria-labelledby="runtime-title">
            <div className="example-runtime__heading">
              <div>
                <p className="kicker">Compiled Dart</p>
                <h2 id="runtime-title">Run it here</h2>
              </div>
              <span>
                <Play size={14} /> isolated browser process
              </span>
            </div>
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
              <p className="kicker">Native capability required</p>
              <h2 id="runtime-title">The browser runner stops at the real boundary.</h2>
              <p>{example.reason}</p>
              <p>
                The source is still indexed below. A future web adapter can make
                this page live without changing its URL.
              </p>
            </div>
          </section>
        )}

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
          <span>{example.runnable ? 'Dart → JavaScript → Cinder WebBackend' : 'Native Dart source'}</span>
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
