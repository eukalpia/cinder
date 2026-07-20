import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { WebTerminal } from '@/components/web-terminal';
import { getExample } from '@/lib/examples';

export const metadata: Metadata = {
  title: 'Cinder Electric City',
  robots: {
    index: false,
    follow: false,
  },
};

export default function CityRuntimePage() {
  const example = getExample('web-showcase');
  if (!example) notFound();

  return (
    <main className="city-runtime-page">
      <WebTerminal
        title={example.title}
        bundle={example.bundle}
        runnable={example.runnable}
        reason={example.reason}
        embedded
      />
    </main>
  );
}
