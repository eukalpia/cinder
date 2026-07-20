'use client';

import Link from 'next/link';
import { Maximize2, Pause, Play, RotateCcw, X } from 'lucide-react';
import { useState } from 'react';
import { HeroCity } from '@/components/hero-city';

export function InteractiveCityLauncher({
  src,
  fullScreenHref,
}: {
  src: string;
  fullScreenHref: string;
}) {
  const [active, setActive] = useState(false);
  const [runtimeKey, setRuntimeKey] = useState(0);

  if (!active) {
    return (
      <div className="city-launcher city-launcher--idle">
        <HeroCity />
        <div className="city-launcher__veil" aria-hidden="true" />
        <div className="city-launcher__prompt">
          <small>● COMPILED CINDER APPLICATION READY</small>
          <strong>Launch the interactive city</strong>
          <span>Mouse · arrows · Tab · Enter · D · E · Space · R</span>
          <div>
            <button type="button" onClick={() => setActive(true)}>
              <Play size={13} fill="currentColor" /> Run here
            </button>
            <Link href={fullScreenHref}>
              <Maximize2 size={13} /> Full screen
            </Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="city-launcher city-launcher--active">
      <header>
        <span><b>●</b> CINDER CITY / WEB BACKEND</span>
        <div>
          <button
            type="button"
            onClick={() => setRuntimeKey((value) => value + 1)}
            aria-label="Restart the Cinder city"
          >
            <RotateCcw size={12} /> Restart
          </button>
          <Link href={fullScreenHref}>
            <Maximize2 size={12} /> Full screen
          </Link>
          <button type="button" onClick={() => setActive(false)} aria-label="Close the inline runtime">
            <X size={13} /> Close
          </button>
        </div>
      </header>
      <iframe
        key={runtimeKey}
        title="Interactive Cinder cyber city"
        src={src}
        loading="eager"
      />
      <footer>
        <span><Pause size={11} /> Space pauses the frame clock</span>
        <span>Click inside before using the keyboard</span>
      </footer>
    </div>
  );
}
