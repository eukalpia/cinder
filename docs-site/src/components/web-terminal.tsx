'use client';

import type { IDisposable, Terminal as XtermTerminal } from '@xterm/xterm';
import { useEffect, useRef, useState } from 'react';

type CinderBridge = {
  width: number | null;
  height: number | null;
  onOutput: ((data: string) => void) | null;
  onInput: ((data: string) => void) | null;
  onResize: ((width: number, height: number) => void) | null;
  onShutdown: (() => void) | null;
};

declare global {
  interface Window {
    cinderBridge?: CinderBridge;
  }
}

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
  const terminalRef = useRef<XtermTerminal | null>(null);
  const [status, setStatus] = useState<'loading' | 'running' | 'failed'>(
    runnable ? 'loading' : 'failed',
  );
  const [failure, setFailure] = useState(reason);

  useEffect(() => {
    if (!runnable || !bundle || !hostRef.current) return;

    const host = hostRef.current;
    const guestBundle = bundle;
    let disposed = false;
    let guestScript: HTMLScriptElement | null = null;
    let resizeObserver: ResizeObserver | null = null;
    let animationFrame: number | null = null;
    const subscriptions: IDisposable[] = [];

    host.dataset.outputWrites = '0';
    host.dataset.inputEvents = '0';
    host.dataset.resizeEvents = '0';
    host.dataset.guestLoaded = 'false';

    async function start() {
      try {
        const [{ Terminal }, { FitAddon }] = await Promise.all([
          import('@xterm/xterm'),
          import('@xterm/addon-fit'),
        ]);

        if (disposed) return;

        const terminal = new Terminal({
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
          screenReaderMode: true,
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
        const fitAddon = new FitAddon();
        terminal.loadAddon(fitAddon);
        terminal.open(host);
        terminalRef.current = terminal;

        const fit = () => {
          if (disposed) return;
          const bounds = host.getBoundingClientRect();
          if (bounds.width < 1 || bounds.height < 1) return;
          try {
            fitAddon.fit();
          } catch {
            // Hidden tabs and freshly mounted iframes can briefly report zero geometry.
          }
        };

        fit();
        animationFrame = requestAnimationFrame(fit);

        const bridge: CinderBridge = {
          width: terminal.cols,
          height: terminal.rows,
          onOutput: (data) => {
            incrementMetric(host, 'outputWrites');
            terminal.write(data);
          },
          onInput: null,
          onResize: null,
          onShutdown: null,
        };
        window.cinderBridge = bridge;
        updateGeometry(host, terminal.cols, terminal.rows);

        const forwardInput = (data: string) => {
          incrementMetric(host, 'inputEvents');
          bridge.onInput?.(data);
        };

        subscriptions.push(
          terminal.onData(forwardInput),
          terminal.onBinary(forwardInput),
          terminal.onResize(({ cols, rows }) => {
            bridge.width = cols;
            bridge.height = rows;
            updateGeometry(host, cols, rows);
            incrementMetric(host, 'resizeEvents');
            bridge.onResize?.(cols, rows);
          }),
        );

        resizeObserver = new ResizeObserver(() => {
          if (animationFrame !== null) cancelAnimationFrame(animationFrame);
          animationFrame = requestAnimationFrame(fit);
        });
        resizeObserver.observe(host);

        guestScript = document.createElement('script');
        guestScript.src = guestBundle;
        guestScript.async = true;
        guestScript.dataset.cinderGuest = title;
        guestScript.onload = () => {
          if (!disposed) {
            host.dataset.guestLoaded = 'true';
            setStatus('running');
            terminal.focus();
          }
        };
        guestScript.onerror = () => {
          if (!disposed) {
            host.dataset.guestLoaded = 'failed';
            setStatus('failed');
            setFailure('The generated Dart bundle could not be loaded.');
          }
        };
        document.body.appendChild(guestScript);
      } catch (error) {
        if (!disposed) {
          host.dataset.guestLoaded = 'failed';
          setStatus('failed');
          setFailure(error instanceof Error ? error.message : String(error));
        }
      }
    }

    void start();

    return () => {
      disposed = true;
      host.dataset.guestLoaded = 'disposed';
      if (animationFrame !== null) cancelAnimationFrame(animationFrame);
      resizeObserver?.disconnect();
      for (const subscription of subscriptions) subscription.dispose();
      window.cinderBridge?.onShutdown?.();
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
          role="application"
          aria-label={`${title} terminal viewport`}
          aria-describedby="web-terminal-help"
          data-runtime-status={status}
          tabIndex={0}
          onClick={() => terminalRef.current?.focus()}
          onFocus={() => terminalRef.current?.focus()}
        />
      ) : (
        <div className="web-terminal__unavailable">
          <strong>This example is intentionally not faked in the browser.</strong>
          <p>{failure ?? 'It requires a native terminal capability.'}</p>
        </div>
      )}
      <footer className="web-terminal__footer" id="web-terminal-help">
        <span>Focus the terminal before typing.</span>
        <span>Rendered by Cinder, hosted by xterm.js.</span>
      </footer>
    </section>
  );
}

function incrementMetric(host: HTMLElement, key: 'outputWrites' | 'inputEvents' | 'resizeEvents') {
  const current = Number(host.dataset[key] ?? '0');
  host.dataset[key] = String(current + 1);
}

function updateGeometry(host: HTMLElement, cols: number, rows: number) {
  host.dataset.cols = String(cols);
  host.dataset.rows = String(rows);
}
