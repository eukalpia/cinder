import type { ReactNode } from 'react';

const cityArt = String.raw`
[[p]]             ╭──────╮                 ╭────────╮                  ╭──────╮[[/]]
[[p]]        ╭────┤░░░░░░├────╮       ╭────┤░░░░░░░░├────╮        ╭────┤░░░░░░├────╮[[/]]
[[p]]     ╭──┤░░░░│░░░░░░│░░░░├──╮ ╭──┤░░░│░░░░░░░░│░░░├──╮  ╭──┤░░░░│░░░░░░│░░░░├──╮[[/]]
[[p]]     │░░│░░░░│░░░░░░│░░░░│░░│ │░░│░░░│░░░░░░░░│░░░│░░│  │░░│░░░░│░░░░░░│░░░░│░░│[[/]]
[[p]]     ╰──┴─┬──┴──┬───┴──┬─┴──╯ ╰──┴──┬┴───┬────┴┬───┴──╯  ╰──┴─┬──┴──┬───┴──┬─┴──╯[[/]]
[[p]]          │     │      │            │    │     │               │     │      │[[/]]
[[p]]   ╭──────┴─────┴──────┴────╮ ╭─────┴────┴─────┴─────╮ ╭───────┴─────┴──────┴──────╮[[/]]
[[p]]╭──┤░░░░░░░░░░░░░░░░░░░░░░├─┤░░░░░░░░░░░░░░░░░░░░░├─┤░░░░░░░░░░░░░░░░░░░░░░░░░├──╮[[/]]
[[p]]│░░│░░░░░░░░░░░░░░░░░░░░░░│░│░░░░░░░░░░░░░░░░░░░░░│░│░░░░░░░░░░░░░░░░░░░░░░░░░│░░│[[/]]
[[p]]╰──┴───────┬──────────┬──────┴─┴──────┬────────┬──────┴─┴────────┬──────────┬───────┴──╯[[/]]
[[p]]            │          │               │        │                 │          │[[/]]
[[o]]         ╭──┴──────────┴───────────────┴────────┴─────────────────┴──────────┴──╮[[/]]
[[o]]         │································································│[[/]]
[[o]]         ╰──────────────╮                      ╭───────────────────────────────╯[[/]]
[[o]]                        ╲                      ╱[[/]]
[[o]]                         ╲                    ╱[[/]]
[[p]]            ╭─────────────╲──────────────────╱─────────────╮[[/]]
[[p]]         ╭──┤░░░░░░░░░░░░╲░░░░░░░░░░░░░░╱░░░░░░░░░░░░├──╮[[/]]
[[p]]         │░░│░░░░░░░░░░░░░╲░░░░░░░░░░░░╱░░░░░░░░░░░░░│░░│[[/]]
[[p]]         ╰──┴──────╮          ╲          ╱          ╭──────┴──╯[[/]]
[[o]]                   ╲          ╭┴────────┴╮         ╱[[/]]
[[o]]                    ╲─────────┤          ├────────╱[[/]]
[[f]]                              │    ░     │[[/]]
[[f]]                              │   ▒▓▒    │[[/]]
[[f]]                              │  ▓███▓   │[[/]]
[[f]]                              │ ▒█████▒  │[[/]]
[[f]]                              │▓███████▓ │[[/]]
[[f]]                              │ ▓█████▓  │[[/]]
[[f]]                              │  ▒███▒   │[[/]]
[[p]]                              │   >_     │[[/]]
[[p]]                         ╭────┴──────────┴────╮[[/]]
[[p]]                    ╭────┤░░░░░░░░░░░░░░░░░░├────╮[[/]]
[[p]]              ╭─────┤░░░│░░░░░░░░░░░░░░░░░░│░░░├─────╮[[/]]
[[p]]              │░░░░░│░░░│░░░░░░░░░░░░░░░░░░│░░░│░░░░░│[[/]]
[[p]]              ╰─────┴────┴──────────────────┴────┴─────╯[[/]]
[[o]]        ╭───────────────╮      ╭───────────────╮      ╭───────────────╮[[/]]
[[o]]        │ EVENT STREAM  │──────│  FRAME DIFF   │──────│  WEB BACKEND  │[[/]]
[[o]]        ╰───────────────╯      ╰───────────────╯      ╰───────────────╯[[/]]`;

const tokenPattern = /\[\[(p|o|f|g)\]\]|\[\[\/\]\]/g;

export function HeroCity() {
  return (
    <div className="hero-city" role="img" aria-label="Isometric terminal city showing the Cinder render pipeline">
      <div className="hero-city__scan" aria-hidden="true" />
      <pre className="hero-city__art" aria-hidden="true">
        {renderCity(cityArt)}
      </pre>
      <div className="hero-city__core" aria-hidden="true">
        <span>WIDGET</span>
        <i>→</i>
        <span>ELEMENT</span>
        <i>→</i>
        <span>DIFF</span>
      </div>
      <div className="hero-city__legend" aria-hidden="true">
        <span><b>●</b> render objects</span>
        <span><b>◆</b> active cells</span>
        <span><b>■</b> damage regions</span>
      </div>
    </div>
  );
}

function renderCity(value: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  let cursor = 0;
  let tone = 'p';
  let key = 0;

  for (const match of value.matchAll(tokenPattern)) {
    const index = match.index ?? 0;
    if (index > cursor) {
      nodes.push(
        <span className={`hero-city__tone hero-city__tone--${tone}`} key={key++}>
          {value.slice(cursor, index)}
        </span>,
      );
    }
    tone = match[1] ?? 'p';
    cursor = index + match[0].length;
  }

  if (cursor < value.length) {
    nodes.push(
      <span className={`hero-city__tone hero-city__tone--${tone}`} key={key++}>
        {value.slice(cursor)}
      </span>,
    );
  }
  return nodes;
}
