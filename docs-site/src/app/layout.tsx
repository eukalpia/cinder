import './globals.css';
import { RootProvider } from 'fumadocs-ui/provider/next';
import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: {
    template: '%s · Cinder',
    default: 'Cinder · Terminal UI framework for Dart',
  },
  description:
    'A Flutter-style Widget, Element, and RenderObject framework for building terminal applications in Dart.',
  applicationName: 'Cinder',
  keywords: [
    'Dart',
    'terminal UI',
    'TUI',
    'Widget framework',
    'Flutter-style',
  ],
  openGraph: {
    title: 'Cinder · Terminal UI framework for Dart',
    description:
      'Build native and browser-hosted terminal applications with a Flutter-style runtime.',
    type: 'website',
  },
};

export const viewport: Viewport = {
  colorScheme: 'dark',
  themeColor: '#090b10',
};

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <body>
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
