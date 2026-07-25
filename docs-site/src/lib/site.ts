export const siteBasePath = normalizeBasePath(
  process.env.NEXT_PUBLIC_BASE_PATH ?? '',
);

export function withBasePath(value: string) {
  if (!value.startsWith('/')) return value;
  if (!siteBasePath) return value;
  if (value === siteBasePath || value.startsWith(`${siteBasePath}/`)) {
    return value;
  }
  return `${siteBasePath}${value}`;
}

function normalizeBasePath(value: string) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}
