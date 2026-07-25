import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { WebTerminal } from '@/components/web-terminal';
import { examples, getExample } from '@/lib/examples';

type PlayPageProps = {
  params: Promise<{ slug: string }>;
};

export const metadata: Metadata = {
  title: 'Cinder web runner',
  robots: {
    index: false,
    follow: false,
  },
};

export function generateStaticParams() {
  return examples.map((example) => ({ slug: example.slug }));
}

export default async function PlayPage({ params }: PlayPageProps) {
  const { slug } = await params;
  const example = getExample(slug);
  if (!example) notFound();

  return (
    <main className="play-page">
      <WebTerminal
        title={example.title}
        bundle={example.bundle}
        runnable={example.runnable}
        reason={example.reason}
      />
    </main>
  );
}
