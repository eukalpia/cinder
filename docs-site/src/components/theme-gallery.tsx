import type { CSSProperties } from 'react';

type ThemePreview = {
  id: string;
  name: string;
  api: string;
  description: string;
  background: string;
  surface: string;
  outline: string;
  foreground: string;
  muted: string;
  primary: string;
  secondary: string;
  success: string;
  warning: string;
  error: string;
  light?: boolean;
};

const themes: readonly ThemePreview[] = [
  {
    id: 'dark',
    name: 'Dark',
    api: 'TuiThemeData.dark',
    description: 'The default Cinder palette: quiet surfaces with a crisp blue focus color.',
    background: '#0d1117',
    surface: '#171b22',
    outline: '#3d4654',
    foreground: '#f0f3f8',
    muted: '#8b95a5',
    primary: '#82aaff',
    secondary: '#c792ea',
    success: '#7bd88f',
    warning: '#ffd866',
    error: '#ff6b7a',
  },
  {
    id: 'light',
    name: 'Light',
    api: 'TuiThemeData.light',
    description: 'A daylight palette with strong text contrast and restrained blue accents.',
    background: '#edf2f7',
    surface: '#ffffff',
    outline: '#9aa7b6',
    foreground: '#18212d',
    muted: '#5d6978',
    primary: '#255ed8',
    secondary: '#7c3aed',
    success: '#16834a',
    warning: '#a85d00',
    error: '#c73645',
    light: true,
  },
  {
    id: 'nord',
    name: 'Nord',
    api: 'TuiThemeData.nord',
    description: 'Arctic blue-gray surfaces with calm cyan and frost-blue interaction states.',
    background: '#242933',
    surface: '#2e3440',
    outline: '#4c566a',
    foreground: '#eceff4',
    muted: '#a6adba',
    primary: '#88c0d0',
    secondary: '#81a1c1',
    success: '#a3be8c',
    warning: '#ebcb8b',
    error: '#bf616a',
  },
  {
    id: 'dracula',
    name: 'Dracula',
    api: 'TuiThemeData.dracula',
    description: 'Deep violet surfaces with the familiar pink, purple, cyan, and green highlights.',
    background: '#191a23',
    surface: '#282a36',
    outline: '#6272a4',
    foreground: '#f8f8f2',
    muted: '#a9a9b3',
    primary: '#bd93f9',
    secondary: '#ff79c6',
    success: '#50fa7b',
    warning: '#f1fa8c',
    error: '#ff5555',
  },
  {
    id: 'catppuccin',
    name: 'Catppuccin Mocha',
    api: 'TuiThemeData.catppuccinMocha',
    description: 'Warm pastel accents over soft dark surfaces for a low-fatigue terminal workspace.',
    background: '#11111b',
    surface: '#1e1e2e',
    outline: '#585b70',
    foreground: '#cdd6f4',
    muted: '#9399b2',
    primary: '#cba6f7',
    secondary: '#89b4fa',
    success: '#a6e3a1',
    warning: '#f9e2af',
    error: '#f38ba8',
  },
  {
    id: 'gruvbox',
    name: 'Gruvbox Dark',
    api: 'TuiThemeData.gruvboxDark',
    description: 'A retro, earthy palette with warm amber focus and deliberately softened contrast.',
    background: '#1d2021',
    surface: '#282828',
    outline: '#665c54',
    foreground: '#ebdbb2',
    muted: '#a89984',
    primary: '#fabd2f',
    secondary: '#83a598',
    success: '#b8bb26',
    warning: '#fe8019',
    error: '#fb4934',
  },
];

export function ThemeGallery() {
  return (
    <section className="theme-gallery" aria-label="Built-in Cinder theme previews">
      {themes.map((theme, index) => {
        const style = {
          '--preview-bg': theme.background,
          '--preview-surface': theme.surface,
          '--preview-outline': theme.outline,
          '--preview-fg': theme.foreground,
          '--preview-muted': theme.muted,
          '--preview-primary': theme.primary,
          '--preview-secondary': theme.secondary,
          '--preview-success': theme.success,
          '--preview-warning': theme.warning,
          '--preview-error': theme.error,
        } as CSSProperties;

        return (
          <article
            className={`theme-preview${theme.light ? ' theme-preview--light' : ''}`}
            style={style}
            key={theme.id}
          >
            <header className="theme-preview__chrome">
              <span className="theme-preview__traffic" aria-hidden="true">
                <i />
                <i />
                <i />
              </span>
              <code>theme_gallery.dart</code>
              <span>{String(index + 1).padStart(2, '0')} / {themes.length}</span>
            </header>

            <div className="theme-preview__terminal">
              <div className="theme-preview__heading">
                <span>CINDER THEME</span>
                <strong>{theme.name}</strong>
              </div>

              <div className="theme-preview__command">
                <span aria-hidden="true">›</span>
                <code>dart run app.dart</code>
                <b>RUNNING</b>
              </div>

              <div className="theme-preview__progress" aria-label="Example progress: 68 percent">
                <span><i /></span>
                <b>68%</b>
              </div>

              <div className="theme-preview__status-grid">
                <span><i className="is-success" /> renderer ready</span>
                <span><i className="is-warning" /> 2 regions dirty</span>
                <span><i className="is-error" /> 0 frame errors</span>
              </div>

              <div className="theme-preview__metrics">
                <span><small>FRAME</small><strong>16.7ms</strong></span>
                <span><small>CELLS</small><strong>4,320</strong></span>
                <span><small>DIFF</small><strong>2.8%</strong></span>
              </div>

              <footer className="theme-preview__keys">
                <span><kbd>1–6</kbd> switch theme</span>
                <span><kbd>T</kbd> toggle</span>
              </footer>
            </div>

            <footer className="theme-preview__meta">
              <div>
                <strong>{theme.name}</strong>
                <code>{theme.api}</code>
                <p>{theme.description}</p>
              </div>
              <div className="theme-preview__palette" aria-label={`${theme.name} palette`}>
                <i style={{ background: theme.primary }} title="Primary" />
                <i style={{ background: theme.secondary }} title="Secondary" />
                <i style={{ background: theme.success }} title="Success" />
                <i style={{ background: theme.warning }} title="Warning" />
                <i style={{ background: theme.error }} title="Error" />
              </div>
            </footer>
          </article>
        );
      })}
    </section>
  );
}
