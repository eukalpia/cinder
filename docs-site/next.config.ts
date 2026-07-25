import { createMDX } from 'fumadocs-mdx/next';
import type { NextConfig } from 'next';

const withMDX = createMDX();
const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH ?? '');

const config: NextConfig = {
  reactStrictMode: true,
  output: 'export',
  trailingSlash: true,
  basePath,
  images: {
    unoptimized: true,
  },
};

function normalizeBasePath(value: string) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}

export default withMDX(config);
