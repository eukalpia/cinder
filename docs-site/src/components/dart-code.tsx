import type { ReactNode } from 'react';

const tokenPattern = /(\/\/.*$|\/\*[\s\S]*?\*\/|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|@\w+|\b(?:import|export|part|library|class|extends|implements|with|mixin|enum|typedef|abstract|sealed|base|interface|final|const|var|late|static|void|return|if|else|switch|case|default|for|while|do|break|continue|try|catch|finally|throw|rethrow|new|this|super|async|await|yield|get|set|operator|on|show|hide|as|is|in|required|covariant|external|factory)\b|\b(?:int|double|num|bool|String|Object|dynamic|Never|Future|Stream|List|Map|Set|Widget|State|BuildContext|Color|TextStyle|EdgeInsets|BoxDecoration|BorderSide|CinderApp|CinderTheme|SchedulerBinding|ScrollController|TextEditingController)\b|\b(?:true|false|null)\b|\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b)/gm;

export function DartCode({
  code,
  className,
  title,
  framed = false,
  lineNumbers = false,
}: {
  code: string;
  className?: string;
  title?: string;
  framed?: boolean;
  lineNumbers?: boolean;
}) {
  const source = (
    <pre
      className={`${className ?? 'tui-code'}${lineNumbers ? ' tui-code--numbered' : ''}`}
      aria-label={title ? `${title} Dart source` : 'Dart source'}
    >
      <code>
        {lineNumbers
          ? code.split('\n').map((line, index) => (
              <span className="tui-code__line" key={index}>
                <span>{highlightDart(line) || ' '}</span>
              </span>
            ))
          : highlightDart(code)}
      </code>
    </pre>
  );

  if (!framed) return source;

  return (
    <section className="code-frame">
      <header className="code-frame__header">
        <span>●</span>
        <span>{title ?? 'main.dart'}</span>
        <strong>DART</strong>
      </header>
      <div className="code-frame__body">{source}</div>
    </section>
  );
}

function highlightDart(code: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  let cursor = 0;

  for (const match of code.matchAll(tokenPattern)) {
    const index = match.index ?? 0;
    if (index > cursor) nodes.push(code.slice(cursor, index));
    const token = match[0];
    nodes.push(
      <span className={`syntax-token ${classify(token)}`} key={`${index}-${token}`}>
        {token}
      </span>,
    );
    cursor = index + token.length;
  }

  if (cursor < code.length) nodes.push(code.slice(cursor));
  return nodes;
}

function classify(token: string) {
  if (token.startsWith('//') || token.startsWith('/*')) return 'syntax-comment';
  if (token.startsWith("'") || token.startsWith('"')) return 'syntax-string';
  if (token.startsWith('@')) return 'syntax-keyword';
  if (/^(?:true|false|null)$/.test(token)) return 'syntax-literal';
  if (/^(?:0x|\d)/.test(token)) return 'syntax-number';
  if (/^[A-Z]/.test(token)) return 'syntax-type';
  return 'syntax-keyword';
}
