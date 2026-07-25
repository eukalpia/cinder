'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { ExamplePreview } from '@/components/example-preview';
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

  const activeFilters = Number(Boolean(query.trim())) + Number(category !== 'All') + Number(runtime !== 'all');
  const runnableCount = filtered.filter((example) => example.runnable).length;

  const clearFilters = () => {
    setQuery('');
    setCategory('All');
    setRuntime('all');
  };

  return (
    <section className="example-index" aria-labelledby="example-index-title">
      <div className="example-index__tools">
        <label className="example-search">
          <span>Find an example</span>
          <div className="example-search__field">
            <span aria-hidden="true">⌕</span>
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="TextField, renderer, image…"
            />
            {query ? (
              <button type="button" onClick={() => setQuery('')} aria-label="Clear search">
                ×
              </button>
            ) : null}
          </div>
        </label>

        <div className="example-filter-group">
          <div className="example-filter-group__label">
            <span>Runtime</span>
            <small>{runtime === 'all' ? 'all modes' : runtimeModeLabel(runtime)}</small>
          </div>
          <div className="runtime-filter" aria-label="Filter examples by runtime mode">
            {runtimeOrder.map((value) => {
              const count =
                value === 'all'
                  ? examples.length
                  : examples.filter((example) => example.runtimeMode === value).length;
              return (
                <button
                  type="button"
                  key={value}
                  className={value === runtime ? 'is-active' : undefined}
                  onClick={() => setRuntime(value)}
                >
                  <span>{value === 'all' ? 'All runtimes' : runtimeModeLabel(value)}</span>
                  <b>{count}</b>
                </button>
              );
            })}
          </div>
        </div>

        <div className="example-filter-group">
          <div className="example-filter-group__label">
            <span>Category</span>
            <small>{category}</small>
          </div>
          <div className="category-filter" aria-label="Filter examples by category">
            {['All', ...categories].map((value) => {
              const count =
                value === 'All'
                  ? examples.length
                  : examples.filter((example) => example.category === value).length;
              return (
                <button
                  type="button"
                  key={value}
                  className={value === category ? 'is-active' : undefined}
                  onClick={() => setCategory(value)}
                >
                  <span>{value}</span>
                  <b>{count}</b>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <div className="example-index__summary" id="example-index-title">
        <div>
          <strong>{filtered.length}</strong>
          <span> detailed previews</span>
          <i>·</i>
          <strong>{runnableCount}</strong>
          <span> live in browser</span>
        </div>
        <div>
          {activeFilters > 0 ? <span>{activeFilters} active filters</span> : <span>Showing the full repository</span>}
          {activeFilters > 0 ? (
            <button type="button" onClick={clearFilters}>Reset filters</button>
          ) : null}
        </div>
      </div>

      <div className="example-gallery">
        {filtered.map((example, index) => {
          const mode = example.runtimeMode ?? (example.runnable ? 'direct-web' : 'native-only');
          return (
            <Link
              href={`/examples/${example.slug}`}
              className="example-card"
              key={example.slug}
            >
              <div className="example-card__preview">
                <ExamplePreview example={example} />
              </div>
              <div className="example-card__content">
                <div className="example-card__heading">
                  <strong>{example.title}</strong>
                  <span className="example-card__index">#{String(index + 1).padStart(2, '0')}</span>
                </div>
                <p className="example-card__description">{example.description}</p>
                <div className="example-card__tags">
                  {(example.tags ?? []).slice(0, 5).map((tag) => (
                    <span key={tag}>{tag}</span>
                  ))}
                </div>
                <div className="example-card__footer">
                  <small>{example.repositoryPath}</small>
                  <b className={`compatibility compatibility--${mode}`}>
                    {runtimeModeLabel(mode)} ↗
                  </b>
                </div>
              </div>
            </Link>
          );
        })}
      </div>

      {filtered.length === 0 ? (
        <div className="example-index__empty">
          <strong>No repository example matches.</strong>
          <p>Try another phrase or clear the active runtime and category filters.</p>
          <button type="button" onClick={clearFilters}>Show all examples</button>
        </div>
      ) : null}
    </section>
  );
}
