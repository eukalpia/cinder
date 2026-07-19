import { defineConfig, devices } from '@playwright/test';

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? '/cinder';
const baseURL = `http://127.0.0.1:4173${basePath}`;

export default defineConfig({
  testDir: './tests/browser',
  outputDir: 'test-results',
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI
    ? [['line'], ['html', { outputFolder: 'playwright-report', open: 'never' }]]
    : 'list',
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    colorScheme: 'dark',
  },
  webServer: {
    command: 'node scripts/serve-export.mjs',
    url: `${baseURL}/`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
    env: {
      NEXT_PUBLIC_BASE_PATH: basePath,
      PORT: '4173',
    },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
