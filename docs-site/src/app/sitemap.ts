import type { MetadataRoute } from 'next';
import { examples } from '@/lib/examples';
import { withBasePath } from '@/lib/site';

export const dynamic = 'force-static';

const siteOrigin = process.env.NEXT_PUBLIC_SITE_ORIGIN ?? 'https://eukalpia.github.io';

function absolute(path: string) {
  return new URL(withBasePath(path), siteOrigin).toString();
}

export default function sitemap(): MetadataRoute.Sitemap {
  const generatedAt = new Date();
  const staticRoutes = [
    '/',
    '/docs/',
    '/docs/installation/',
    '/docs/first-app/',
    '/docs/web-runtime/',
    '/docs/reference/',
    '/examples/',
    '/api/',
  ];

  return [
    ...staticRoutes.map((route) => ({
      url: absolute(route),
      lastModified: generatedAt,
      changeFrequency: route === '/' ? ('weekly' as const) : ('monthly' as const),
      priority: route === '/' ? 1 : route === '/examples/' ? 0.9 : 0.8,
    })),
    ...examples.map((example) => ({
      url: absolute(`/examples/${example.slug}/`),
      lastModified: generatedAt,
      changeFrequency: 'monthly' as const,
      priority: example.runnable ? 0.75 : 0.6,
    })),
  ];
}
