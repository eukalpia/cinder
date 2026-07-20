import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { WebTerminal } from '@/components/web-terminal';
import { getExample } from '@/lib/examples';

export const metadata: Metadata = {
  title: 'Interactive Cinder city',
  robots: {
    index: false,
    follow: false,
  },
};

export default function InteractiveCityPage() {
  const example = getExample('web-showcase');
  if (!example) notFound();

  return (
    <main className="city-showcase-page">
      <WebTerminal
        title={example.title}
        bundle={example.bundle}
        runnable={example.runnable}
        reason={example.reason}
        chrome={false}
        fontSize={8.5}
        scrollback={0}
      />
    </main>
  );
}
