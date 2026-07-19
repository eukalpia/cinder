'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import type { CinderExample } from '@/lib/examples';

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

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return examples.filter((example) => {
      const matchesCategory = category === 'All' || example.category === category;
      const matchesQuery =
        !needle ||
        `${example.title} ${example.description} ${example.repositoryPath}`
          .toLowerCase()
          .includes(needle);
      return matchesCategory && matchesQuery;
    });
  }, [category, examples, query]);

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
        {filtered.map((example, index) => (
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
            <span
              className={`compatibility compatibility--${example.runnable ? 'web' : 'native'}`}
            >
              {example.runnable ? 'Live web' : 'Native only'}
            </span>
            <span className="example-ledger__arrow" aria-hidden="true">
              ↗
            </span>
          </Link>
        ))}
        {filtered.length === 0 ? (
          <div className="example-index__empty">
            No invented result. Change the search or category.
          </div>
        ) : null}
      </div>
    </section>
  );
}
