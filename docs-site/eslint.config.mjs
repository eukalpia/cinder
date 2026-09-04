import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  globalIgnores([
    '.next/**',
    '.source/**',
    'out/**',
    'build/**',
    'public/generated/**',
    'public/api/**',
    'test-results/**',
    'playwright-report/**',
    'next-env.d.ts',
  ]),
]);

export default eslintConfig;
