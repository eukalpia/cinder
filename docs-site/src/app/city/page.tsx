import type { Metadata } from 'next';
import Link from 'next/link';
import { HeroCity } from '@/components/hero-city';

export const metadata: Metadata = {
  title: 'Cinder City runtime',
  robots: {
    index: false,
    follow: false,
  },
};

export default function CityRuntimePage() {
  return (
    <main className="city-runtime-page">
      <section
        className="tui-panel control-scene"
        aria-label="Cinder city runtime launcher"
        style={{ minHeight: '100dvh', height: '100dvh' }}
      >
        <div className="control-scene-title">CINDER CITY // WEB RUNTIME</div>
        <HeroCity />
        <Link
          href="/play/web-showcase"
          style={{
            position: 'absolute',
            right: 'clamp(12px, 2vw, 24px)',
            bottom: 'clamp(12px, 2vw, 24px)',
            left: 'clamp(12px, 2vw, 24px)',
            zIndex: 10,
            display: 'grid',
            gap: '8px',
            padding: 'clamp(14px, 2vw, 20px)',
            border: '1px solid rgba(255, 132, 35, 0.6)',
            background: 'rgba(3, 4, 9, 0.94)',
            color: '#ff8423',
            fontFamily: 'var(--tui-mono)',
            boxShadow: '0 0 40px rgba(203, 95, 255, 0.16)',
          }}
        >
          <small style={{ color: '#7ee28e' }}>● COMPILED CINDER APPLICATION READY</small>
          <strong>OPEN INTERACTIVE CITY ↗</strong>
          <small style={{ color: '#8f879a' }}>
            Mouse · arrows · Tab · Enter · D · E · Space · R
          </small>
        </Link>
      </section>
    </main>
  );
}
