import Link from 'next/link';
import { cinderVersion } from '@/lib/examples';
import { withBasePath } from '@/lib/site';

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link href="/" className="site-brand" aria-label="Cinder home">
        <img src={withBasePath('/cinder-logo.png')} alt="" />
        <span className="site-brand__name">Cinder</span>
        <span className="site-brand__version">{cinderVersion}</span>
      </Link>
      <nav className="site-nav" aria-label="Primary navigation">
        <Link href="/docs">Docs</Link>
        <Link href="/examples">Examples</Link>
        <a href="https://github.com/eukalpia/cinder">GitHub</a>
      </nav>
    </header>
  );
}
