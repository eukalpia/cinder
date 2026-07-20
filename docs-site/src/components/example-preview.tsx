import type { CSSProperties, ReactNode } from 'react';
import type { CinderExample } from '@/lib/examples';

export function ExamplePreview({
  example,
  compact = false,
}: {
  example: CinderExample;
  compact?: boolean;
}) {
  const seed = hash(example.slug);
  const variant = example.slug === 'web-showcase' ? 'city' : variantFor(example);

  return (
    <div
      className={`example-preview example-preview--${variant}${compact ? ' example-preview--compact' : ''}`}
      aria-label={`${example.title} preview`}
    >
      <header>
        <span>● {example.slug}.dart</span>
        <span>{example.category.toUpperCase()}</span>
      </header>
      <div className="example-preview__body">
        {renderVariant(variant, seed, example)}
      </div>
      <footer>
        <span>{example.runtimeMode ?? 'direct-web'}</span>
        <span>{String((seed % 54) + 7).padStart(2, '0')} widgets</span>
        <span>{example.runnable ? 'LIVE' : 'SOURCE'}</span>
      </footer>
    </div>
  );
}

function renderVariant(
  variant: PreviewVariant,
  seed: number,
  example: CinderExample,
): ReactNode {
  switch (variant) {
    case 'city':
      return <CityPreview seed={seed} />;
    case 'editor':
      return <EditorPreview seed={seed} />;
    case 'files':
      return <FilesPreview seed={seed} />;
    case 'monitor':
      return <MonitorPreview seed={seed} />;
    case 'input':
      return <InputPreview seed={seed} />;
    case 'media':
      return <MediaPreview seed={seed} example={example} />;
    case 'navigation':
      return <NavigationPreview seed={seed} />;
    case 'motion':
      return <MotionPreview seed={seed} />;
    case 'table':
      return <TablePreview seed={seed} />;
    default:
      return <DashboardPreview seed={seed} title={example.title} />;
  }
}

function CityPreview({ seed }: { seed: number }) {
  const lights = series(seed, 18, 1, 5);
  return (
    <div className="preview-city" aria-hidden="true">
      <div className="preview-city__sky">
        {lights.map((value, index) => (
          <i
            key={index}
            style={
              {
                '--x': `${(index * 37 + seed) % 100}%`,
                '--y': `${(index * 23 + seed) % 58}%`,
                '--glow': value,
              } as CSSProperties
            }
          />
        ))}
      </div>
      <pre>{`     ╱╲       ╱╲       ╱╲\n  ╭──┴─╮   ╭──┴──╮  ╭──┴─╮\n  │▓░▓░│═══│░▓░▓░│══│▓░▓░│\n╭─┴────┴───┴─────┴──┴────┴─╮\n│        ░▒▓ CINDER ▓▒░      │\n╰══╦════════╦════════╦═══════╯\n   ║  ╱╲    ║   ╱╲   ║\n   ╚═╱__╲═══╩══╱__╲══╝`}</pre>
      <span>FRAME 16.7ms</span>
    </div>
  );
}

function DashboardPreview({ seed, title }: { seed: number; title: string }) {
  const bars = series(seed, 18, 2, 12);
  return (
    <div className="preview-dashboard">
      <aside>
        <b>{shorten(title, 16)}</b>
        <span className="is-active">› Overview</span>
        <span>Widgets</span>
        <span>Events</span>
        <span>Logs</span>
      </aside>
      <div className="preview-dashboard__main">
        <label>FRAME ACTIVITY</label>
        <div className="preview-bars">
          {bars.map((height, index) => (
            <i key={index} style={{ '--bar': height } as CSSProperties} />
          ))}
        </div>
        <div className="preview-metrics">
          <span><b>FPS</b><em>60</em></span>
          <span><b>DIFF</b><em>{seed % 240}</em></span>
          <span><b>MS</b><em>{((seed % 23) / 10 + 1).toFixed(1)}</em></span>
        </div>
      </div>
    </div>
  );
}

function EditorPreview({ seed }: { seed: number }) {
  return (
    <div className="preview-editor">
      <nav aria-label="Preview files">
        <span>▾ lib</span>
        <span>  app.dart</span>
        <span>  screen.dart</span>
        <span>  theme.dart</span>
      </nav>
      <pre>
        <span className="ln">1</span> <b>class</b> <i>Dashboard</i> <b>extends</b> Widget {'{'}{`\n`}
        <span className="ln">2</span>   <b>const</b> Dashboard();{`\n`}
        <span className="ln">3</span>   Widget build(ctx) {'{'}{`\n`}
        <span className="ln">4</span>     <b>return</b> Column(...);{`\n`}
        <span className="ln">5</span>   {'}'} <small>{'// '}{seed % 99} cells</small>{`\n`}
        <span className="ln">6</span> {'}'}
      </pre>
    </div>
  );
}

function FilesPreview({ seed }: { seed: number }) {
  const selected = seed % 4;
  const files = ['lib/', 'widgets/', 'render.dart', 'input.dart', 'theme.dart'];
  return (
    <div className="preview-files">
      <aside>
        {files.map((file, index) => (
          <span className={index === selected ? 'is-active' : ''} key={file}>
            {index < 2 ? '▾' : '├'} {file}
          </span>
        ))}
      </aside>
      <div className="preview-files__main">
        <b>PROJECT INFO</b>
        <dl>
          <dt>FILES</dt><dd>{(seed % 180) + 22}</dd>
          <dt>LINES</dt><dd>{(seed % 8000) + 1200}</dd>
          <dt>STATUS</dt><dd>clean</dd>
        </dl>
      </div>
    </div>
  );
}

function MonitorPreview({ seed }: { seed: number }) {
  return (
    <div className="preview-monitor">
      {['CPU', 'MEM', 'NET', 'IO'].map((label, row) => (
        <div key={label}>
          <span>{label}</span>
          <div className="preview-bars">
            {series(seed + row * 11, 22, 1, 9).map((height, index) => (
              <i key={index} style={{ '--bar': height } as CSSProperties} />
            ))}
          </div>
          <em>{(seed + row * 17) % 100}%</em>
        </div>
      ))}
    </div>
  );
}

function InputPreview({ seed }: { seed: number }) {
  return (
    <div className="preview-input">
      <label>PROFILE NAME</label>
      <div><span>cinder-user-{seed % 99}</span><i>│</i></div>
      <label>RUNTIME</label>
      <div className="preview-choice"><b>● Web</b><span>○ Native</span><span>○ SSH</span></div>
      <span className="preview-input__action">[ Enter ] APPLY</span>
    </div>
  );
}

function MediaPreview({ seed, example }: { seed: number; example: CinderExample }) {
  const text = `${example.title} ${example.slug}`.toLowerCase();
  const isVideo = /video|movie|player/.test(text);
  const isAudio = /audio|sound|wave/.test(text);

  return (
    <div className={`preview-media preview-media--${isVideo ? 'video' : isAudio ? 'audio' : 'image'}`}>
      <div className="preview-media__canvas">
        {isAudio ? (
          <div className="preview-media__wave" aria-hidden="true">
            {series(seed, 34, 1, 10).map((height, index) => (
              <i key={index} style={{ '--bar': height } as CSSProperties} />
            ))}
          </div>
        ) : (
          <svg viewBox="0 0 320 180" role="img" aria-label={`${example.title} generated preview`}>
            <defs>
              <linearGradient id={`sky-${seed}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor="#12071f" />
                <stop offset="0.55" stopColor="#37104d" />
                <stop offset="1" stopColor="#09050d" />
              </linearGradient>
              <linearGradient id={`sun-${seed}`} x1="0" y1="0" x2="1" y2="1">
                <stop offset="0" stopColor="#ffca55" />
                <stop offset="1" stopColor="#ff5f38" />
              </linearGradient>
            </defs>
            <rect width="320" height="180" fill={`url(#sky-${seed})`} />
            <circle cx="238" cy="52" r="28" fill={`url(#sun-${seed})`} opacity="0.94" />
            <path d="M0 132 L48 87 L82 116 L126 68 L171 124 L218 83 L320 139 V180 H0 Z" fill="#110b1d" />
            <path d="M0 151 L61 112 L102 143 L157 104 L205 146 L263 111 L320 151 V180 H0 Z" fill="#261039" />
            <g fill="#08070d" stroke="#b85af4" strokeWidth="2">
              <path d="M32 150 V97 H76 V150" />
              <path d="M91 150 V75 H139 V150" />
              <path d="M153 150 V104 H197 V150" />
              <path d="M211 150 V89 H269 V150" />
            </g>
            <g fill="#ff8a2b">
              {Array.from({ length: 18 }, (_, index) => {
                const x = 39 + (index % 3) * 11 + Math.floor(index / 6) * 59;
                const y = 107 + Math.floor(index / 3) % 4 * 10;
                return <rect key={index} x={x} y={y} width="5" height="3" opacity={(index + seed) % 4 === 0 ? 0.25 : 0.9} />;
              })}
            </g>
            {isVideo ? (
              <g transform="translate(145 70)">
                <circle r="24" fill="#05070b" opacity="0.82" stroke="#ff8a2b" />
                <path d="M-6 -11 L13 0 L-6 11 Z" fill="#f7e9ff" />
              </g>
            ) : null}
          </svg>
        )}
        <span className="preview-media__badge">{isVideo ? '▶ VIDEO' : isAudio ? '♫ AUDIO' : '▣ IMAGE'}</span>
      </div>
      <div className="preview-media__details">
        <span>FRAME {(seed % 240) + 1}</span>
        <span>{isAudio ? '48 kHz stereo' : 'RGBA 320×180'}</span>
        <span>{isVideo ? '60 FPS STREAM' : isAudio ? 'PCM BUFFER' : 'CINDER IMAGE CELL'}</span>
      </div>
    </div>
  );
}

function NavigationPreview({ seed }: { seed: number }) {
  const active = seed % 5;
  return (
    <div className="preview-navigation">
      <aside>
        {['Overview', 'Widgets', 'Events', 'Performance', 'Settings'].map((item, index) => (
          <span className={index === active ? 'is-active' : ''} key={item}>› {item}</span>
        ))}
      </aside>
      <div className="preview-navigation__main">
        <div className="preview-route">/app/{active}/details</div>
        <div className="preview-route-map">HOME → STACK → PAGE → DIALOG</div>
      </div>
    </div>
  );
}

function MotionPreview({ seed }: { seed: number }) {
  const position = seed % 74;
  return (
    <div className="preview-motion">
      <div className="preview-track"><i style={{ left: `${position}%` }} /></div>
      <pre>◜──────────────◝{`\n`}│  FRAME LOOP  │{`\n`}◟──────────────◞</pre>
      <div className="preview-timeline">00:00 ━━━━━●━━━━━ 00:16</div>
    </div>
  );
}

function TablePreview({ seed }: { seed: number }) {
  return (
    <table className="preview-table">
      <thead><tr><th>ID</th><th>WIDGET</th><th>FPS</th><th>STATE</th></tr></thead>
      <tbody>
        {Array.from({ length: 5 }, (_, index) => (
          <tr key={index}>
            <td>{String(index + 1).padStart(2, '0')}</td>
            <td>{['ListView', 'TextField', 'Dialog', 'TreeView', 'Image'][index]}</td>
            <td>{58 + ((seed + index) % 3)}</td>
            <td>{index === seed % 5 ? 'ACTIVE' : 'IDLE'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function variantFor(example: CinderExample): PreviewVariant {
  const text = `${example.category} ${example.title} ${example.tags?.join(' ') ?? ''}`.toLowerCase();
  if (/editor|code|markdown/.test(text)) return 'editor';
  if (/file|tree/.test(text)) return 'files';
  if (/monitor|chart|log|performance/.test(text)) return 'monitor';
  if (/input|field|form|keyboard|focus/.test(text)) return 'input';
  if (/image|video|audio|media/.test(text)) return 'media';
  if (/navigation|route|menu|tabs|dialog|overlay/.test(text)) return 'navigation';
  if (/animation|motion|progress|spinner|transition/.test(text)) return 'motion';
  if (/table|data|list|grid/.test(text)) return 'table';
  return 'dashboard';
}

type PreviewVariant =
  | 'city'
  | 'dashboard'
  | 'editor'
  | 'files'
  | 'monitor'
  | 'input'
  | 'media'
  | 'navigation'
  | 'motion'
  | 'table';

function series(seed: number, count: number, min: number, max: number) {
  const range = max - min + 1;
  return Array.from(
    { length: count },
    (_, index) => min + ((seed + index * 13 + index * index * 3) % range),
  );
}

function hash(value: string) {
  let result = 2166136261;
  for (let index = 0; index < value.length; index++) {
    result ^= value.charCodeAt(index);
    result = Math.imul(result, 16777619);
  }
  return Math.abs(result >>> 0);
}

function shorten(value: string, max: number) {
  return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}
