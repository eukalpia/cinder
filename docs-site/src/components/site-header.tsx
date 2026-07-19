import Link from 'next/link';
import { cinderVersion } from '@/lib/examples';
import { withBasePath } from '@/lib/site';

const links = [
  ['1', 'Docs', '/docs'],
  ['2', 'Examples', '/examples'],
  ['3', 'API', '/api'],
  ['4', 'Reference', '/docs/reference'],
] as const;

export function SiteHeader() {
  return (
    <header className="site-header site-header--tui">
      <Link href="/" className="site-brand" aria-label="Cinder home">
        <img src={withBasePath('/cinder-logo.png')} alt="Cinder" />
        <span className="site-brand__name">Cinder</span>
      </Link>

      <nav className="site-nav site-nav--indexed" aria-label="Primary navigation">
        {links.map(([key, label, href]) => (
          <Link href={href} key={href}>
            <span>[{key}]</span> {label}
          </Link>
        ))}
        <a href="https://github.com/eukalpia/cinder">
          <span>[5]</span> GitHub
        </a>
      </nav>

      <div className="site-runtime-state" aria-label="Cinder web runtime available">
        <span className="site-brand__version">{cinderVersion}</span>
        <strong>● WEB RUNTIME AVAILABLE</strong>
      </div>
    </header>
  );
}
