'use client';

import { useEffect, useRef, useState } from 'react';

type CinderBridge = {
  width: number | null;
  height: number | null;
  onOutput: ((data: string) => void) | null;
  onInput: ((data: string) => void) | null;
  onResize: ((width: number, height: number) => void) | null;
  onShutdown: (() => void) | null;
};

type XtermDisposable = { dispose(): void };

type XtermInstance = {
  cols: number;
  rows: number;
  open(element: HTMLElement): void;
  write(data: string): void;
  focus(): void;
  dispose(): void;
  loadAddon(addon: unknown): void;
  onData(callback: (data: string) => void): XtermDisposable;
  onResize(
    callback: (size: { cols: number; rows: number }) => void,
  ): XtermDisposable;
};

type FitAddonInstance = {
  fit(): void;
};

declare global {
  interface Window {
    Terminal?: new (options: Record<string, unknown>) => XtermInstance;
    FitAddon?: {
      FitAddon: new () => FitAddonInstance;
    };
    cinderBridge?: CinderBridge;
  }
}

const xtermScript = 'https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js';
const fitScript =
  'https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js';
const xtermStyles =
  'https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css';

export function WebTerminal({
  title,
  bundle,
  runnable,
  reason,
}: {
  title: string;
  bundle: string | null;
  runnable: boolean;
  reason: string | null;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const terminalRef = useRef<XtermInstance | null>(null);
  const [status, setStatus] = useState<'loading' | 'running' | 'failed'>(
    runnable ? 'loading' : 'failed',
  );
  const [failure, setFailure] = useState(reason);

  useEffect(() => {
    if (!runnable || !bundle || !hostRef.current) return;

    let disposed = false;
    let guestScript: HTMLScriptElement | null = null;
    let resizeObserver: ResizeObserver | null = null;
    const subscriptions: XtermDisposable[] = [];

    async function start() {
      try {
        installStylesheet(xtermStyles);
        await loadScript(xtermScript, 'xterm-core');
        await loadScript(fitScript, 'xterm-fit');

        if (
          disposed ||
          !hostRef.current ||
          !window.Terminal ||
          !window.FitAddon
        ) {
          return;
        }

        const terminal = new window.Terminal({
          cursorBlink: true,
          cursorStyle: 'bar',
          cursorWidth: 1,
          fontFamily:
            '"IBM Plex Mono", "JetBrains Mono", "Cascadia Code", ui-monospace, monospace',
          fontSize: 13,
          lineHeight: 1.12,
          letterSpacing: 0,
          scrollback: 1000,
          allowTransparency: false,
          convertEol: false,
          drawBoldTextInBrightColors: false,
          theme: {
            background: '#090b10',
            foreground: '#d8d5e2',
            cursor: '#ff8b3d',
            cursorAccent: '#090b10',
            selectionBackground: '#55311f',
            black: '#090b10',
            red: '#ff6b73',
            green: '#8dc891',
            yellow: '#e6bf69',
            blue: '#8ea7d8',
            magenta: '#aa8ee8',
            cyan: '#77bec2',
            white: '#d8d5e2',
            brightBlack: '#626775',
            brightRed: '#ff858b',
            brightGreen: '#a4d9a7',
            brightYellow: '#f0ce82',
            brightBlue: '#a7bce6',
            brightMagenta: '#c0a8f2',
            brightCyan: '#91d0d3',
            brightWhite: '#ffffff',
          },
        });
        const fitAddon = new window.FitAddon.FitAddon();
        terminal.loadAddon(fitAddon);
        terminal.open(hostRef.current);
        terminalRef.current = terminal;

        const fit = () => {
          if (disposed) return;
          try {
            fitAddon.fit();
          } catch {
            // xterm can report zero geometry while a tab is hidden.
          }
        };

        fit();
        requestAnimationFrame(fit);

        const bridge: CinderBridge = {
          width: terminal.cols,
          height: terminal.rows,
          onOutput: (data) => terminal.write(data),
          onInput: null,
          onResize: null,
          onShutdown: null,
        };
        window.cinderBridge = bridge;

        subscriptions.push(
          terminal.onData((data) => bridge.onInput?.(data)),
          terminal.onResize(({ cols, rows }) => {
            bridge.width = cols;
            bridge.height = rows;
            bridge.onResize?.(cols, rows);
          }),
        );

        resizeObserver = new ResizeObserver(() => {
          requestAnimationFrame(fit);
        });
        resizeObserver.observe(hostRef.current);

        guestScript = document.createElement('script');
        guestScript.src = bundle;
        guestScript.async = true;
        guestScript.dataset.cinderGuest = title;
        guestScript.onload = () => {
          if (!disposed) {
            setStatus('running');
            terminal.focus();
          }
        };
        guestScript.onerror = () => {
          if (!disposed) {
            setStatus('failed');
            setFailure('The generated Dart bundle could not be loaded.');
          }
        };
        document.body.appendChild(guestScript);
      } catch (error) {
        if (!disposed) {
          setStatus('failed');
          setFailure(error instanceof Error ? error.message : String(error));
        }
      }
    }

    void start();

    return () => {
      disposed = true;
      resizeObserver?.disconnect();
      for (const subscription of subscriptions) subscription.dispose();
      guestScript?.remove();
      terminalRef.current?.dispose();
      terminalRef.current = null;
      delete window.cinderBridge;
    };
  }, [bundle, runnable, title]);

  return (
    <section className="web-terminal" aria-label={`${title} live terminal`}>
      <header className="web-terminal__bar">
        <div className="web-terminal__identity">
          <span className="web-terminal__prompt" aria-hidden="true">
            &gt;_
          </span>
          <span>{title}</span>
        </div>
        <div className="web-terminal__actions">
          <span className={`runtime-state runtime-state--${status}`}>
            {status === 'loading'
              ? 'booting'
              : status === 'running'
                ? 'browser runtime'
                : 'source only'}
          </span>
          {runnable ? (
            <button type="button" onClick={() => window.location.reload()}>
              Restart
            </button>
          ) : null}
        </div>
      </header>
      {runnable ? (
        <div
          ref={hostRef}
          className="web-terminal__viewport"
          onClick={() => terminalRef.current?.focus()}
        />
      ) : (
        <div className="web-terminal__unavailable">
          <strong>This example is intentionally not faked in the browser.</strong>
          <p>{failure ?? 'It requires a native terminal capability.'}</p>
        </div>
      )}
      <footer className="web-terminal__footer">
        <span>Click the terminal before typing.</span>
        <span>Rendered by Cinder, hosted by xterm.js.</span>
      </footer>
    </section>
  );
}

function installStylesheet(href: string) {
  if (document.querySelector(`link[href="${href}"]`)) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  document.head.appendChild(link);
}

function loadScript(src: string, id: string) {
  const existing = document.querySelector<HTMLScriptElement>(
    `script[data-cinder-runtime="${id}"]`,
  );
  if (existing?.dataset.loaded === 'true') return Promise.resolve();

  return new Promise<void>((resolve, reject) => {
    const script = existing ?? document.createElement('script');
    script.dataset.cinderRuntime = id;
    script.src = src;
    script.async = true;
    script.addEventListener(
      'load',
      () => {
        script.dataset.loaded = 'true';
        resolve();
      },
      { once: true },
    );
    script.addEventListener(
      'error',
      () => reject(new Error(`Failed to load ${src}`)),
      { once: true },
    );
    if (!existing) document.head.appendChild(script);
  });
}
