import type { MetadataRoute } from 'next';
import { withBasePath } from '@/lib/site';

const siteOrigin = process.env.NEXT_PUBLIC_SITE_ORIGIN ?? 'https://eukalpia.github.io';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: '*',
      allow: '/',
      disallow: [withBasePath('/play/')],
    },
    sitemap: new URL(withBasePath('/sitemap.xml'), siteOrigin).toString(),
  };
}
