'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import {
  runtimeModeLabel,
  type CinderExample,
  type CinderRuntimeMode,
} from '@/lib/examples';

type RuntimeFilter = 'all' | CinderRuntimeMode;

const runtimeOrder: RuntimeFilter[] = [
  'all',
  'direct-web',
  'browser-adapter',
  'browser-sandbox',
  'native-only',
  'build-failed',
];

export function ExampleDeck({ examples }: { examples: CinderExample[] }) {
  const categories = useMemo(
    () =>
      Array.from(new Set(examples.map((example) => example.category))).sort(
        (left, right) => left.localeCompare(right),
      ),
    [examples],
  );
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('All');
  const [runtime, setRuntime] = useState<RuntimeFilter>('all');

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return examples.filter((example) => {
      const matchesCategory = category === 'All' || example.category === category;
      const matchesRuntime = runtime === 'all' || example.runtimeMode === runtime;
      const matchesQuery =
        !needle ||
        `${example.title} ${example.description} ${example.repositoryPath} ${example.tags?.join(' ') ?? ''} ${example.runtimeMode ?? ''}`
          .toLowerCase()
          .includes(needle);
      return matchesCategory && matchesRuntime && matchesQuery;
    });
  }, [category, examples, query, runtime]);

  return (
    <section className="example-index" aria-labelledby="example-index-title">
      <div className="example-index__tools">
        <label className="example-search">
          <span>Find an example</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="TextField, renderer, image…"
          />
        </label>

        <div className="runtime-filter" aria-label="Filter examples by runtime mode">
          {runtimeOrder.map((value) => (
            <button
              type="button"
              key={value}
              className={value === runtime ? 'is-active' : undefined}
              onClick={() => setRuntime(value)}
            >
              {value === 'all' ? 'All runtimes' : runtimeModeLabel(value)}
            </button>
          ))}
        </div>

        <div className="category-filter" aria-label="Filter examples by category">
          {['All', ...categories].map((value) => (
            <button
              type="button"
              key={value}
              className={value === category ? 'is-active' : undefined}
              onClick={() => setCategory(value)}
            >
              {value}
            </button>
          ))}
        </div>
      </div>

      <div className="example-index__summary" id="example-index-title">
        <span>{filtered.length} entries</span>
        <span>
          {filtered.filter((example) => example.runnable).length} run in the browser
        </span>
      </div>

      <div className="example-ledger">
        {filtered.map((example, index) => {
          const mode = example.runtimeMode ?? (example.runnable ? 'direct-web' : 'native-only');
          return (
            <Link
              href={`/examples/${example.slug}`}
              className="example-ledger__row"
              key={example.slug}
            >
              <span className="example-ledger__number">
                {String(index + 1).padStart(2, '0')}
              </span>
              <span className="example-ledger__main">
                <strong>{example.title}</strong>
                <small>{example.description}</small>
              </span>
              <span className="example-ledger__category">{example.category}</span>
              <span className={`compatibility compatibility--${mode}`}>
                {runtimeModeLabel(mode)}
              </span>
              <span className="example-ledger__arrow" aria-hidden="true">
                ↗
              </span>
            </Link>
          );
        })}
        {filtered.length === 0 ? (
          <div className="example-index__empty">
            No matching repository example. Change the search or filters.
          </div>
        ) : null}
      </div>
    </section>
  );
}
