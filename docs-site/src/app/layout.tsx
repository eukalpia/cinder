import '@xterm/xterm/css/xterm.css';
import './globals.css';
import './tui.css';
import './control-room.css';
import './city-runtime.css';
import './site-polish.css';
import './site-polish-fixes.css';
import './a11y.css';
import './runtime-modes.css';
import './responsive-overhaul.css';
import './responsive-corrections.css';
import './example-ui-polish.css';
import { RootProvider } from 'fumadocs-ui/provider/next';
import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { siteBasePath, withBasePath } from '@/lib/site';

const siteOrigin = process.env.NEXT_PUBLIC_SITE_ORIGIN ?? 'https://eukalpia.github.io';
const canonicalRoot = siteBasePath ? `${siteBasePath}/` : '/';

export const metadata: Metadata = {
  metadataBase: new URL(siteOrigin),
  title: {
    template: '%s · Cinder',
    default: 'Cinder · Terminal UI framework for Dart',
  },
  description:
    'Cinder is a Flutter-style Widget, Element, and RenderObject framework for building interactive terminal applications in Dart, with native and browser terminal backends.',
  applicationName: 'Cinder',
  category: 'Developer Tools',
  authors: [{ name: 'Cinder contributors', url: 'https://github.com/eukalpia/cinder' }],
  creator: 'Cinder contributors',
  publisher: 'Cinder contributors',
  keywords: [
    'Cinder',
    'Dart terminal UI',
    'Dart TUI framework',
    'terminal user interface',
    'Flutter-style widgets',
    'RenderObject terminal',
    'xterm.js Dart',
    'command line interface framework',
    'cross-platform TUI',
  ],
  alternates: { canonical: canonicalRoot },
  manifest: withBasePath('/site.webmanifest'),
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet': -1,
      'max-video-preview': -1,
    },
  },
  openGraph: {
    title: 'Cinder · Terminal UI framework for Dart',
    description:
      'Build native and browser-hosted terminal applications with Widget, Element, State, BuildContext, and RenderObject architecture.',
    type: 'website',
    url: canonicalRoot,
    siteName: 'Cinder',
    locale: 'en_US',
    images: [
      {
        url: withBasePath('/og-cinder.svg'),
        width: 1200,
        height: 630,
        alt: 'Cinder terminal UI framework for Dart',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Cinder · Terminal UI framework for Dart',
    description:
      'A Flutter-style terminal UI framework for Dart with a real browser terminal runtime.',
    images: [withBasePath('/og-cinder.svg')],
  },
};

export const viewport: Viewport = {
  colorScheme: 'dark',
  themeColor: '#030409',
  width: 'device-width',
  initialScale: 1,
};

const structuredData = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'WebSite',
      name: 'Cinder',
      url: new URL(canonicalRoot, siteOrigin).toString(),
      description:
        'Documentation, examples, and browser runners for the Cinder terminal UI framework.',
    },
    {
      '@type': 'SoftwareSourceCode',
      name: 'Cinder',
      description:
        'A Flutter-style, high-performance terminal UI framework for Dart.',
      codeRepository: 'https://github.com/eukalpia/cinder',
      programmingLanguage: 'Dart',
      runtimePlatform: ['Windows', 'macOS', 'Linux', 'Web browser'],
      license: 'https://www.apache.org/licenses/LICENSE-2.0',
      isAccessibleForFree: true,
    },
  ],
};

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <body>
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        <RootProvider>
          <div id="main-content" tabIndex={-1}>
            {children}
          </div>
        </RootProvider>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
        />
      </body>
    </html>
  );
}
