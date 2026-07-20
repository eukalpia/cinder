import { HeroCity } from '@/components/hero-city';
import { withBasePath } from '@/lib/site';

export function InteractiveHeroCity() {
  return (
    <div className="interactive-hero-city">
      <iframe
        title="Interactive Cinder terminal city"
        src={withBasePath('/showcase/city/')}
        className="interactive-hero-city__runtime"
        loading="eager"
      />
      <div className="interactive-hero-city__fallback">
        <HeroCity />
      </div>
      <div className="interactive-hero-city__hint" aria-hidden="true">
        <span>HOVER BUILDINGS</span>
        <span>CLICK TO BOOST</span>
        <span>ARROWS TO NAVIGATE</span>
        <span>SPACE TO PAUSE</span>
      </div>
    </div>
  );
}
