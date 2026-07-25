'use client';

import { useState } from 'react';

export function CopyCommand({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button type="button" onClick={copy} aria-live="polite">
      {copied ? '[copied]' : '[copy]'}
    </button>
  );
}
