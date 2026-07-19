import { expect, test, type Page } from '@playwright/test';

type ExampleManifest = {
  examples: Array<{
    slug: string;
    title: string;
    runnable: boolean;
  }>;
};

function failOnPageErrors(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  return () => expect(errors, errors.join('\n')).toEqual([]);
}

test('homepage presents Cinder as a terminal control surface', async ({ page }, testInfo) => {
  const assertNoPageErrors = failOnPageErrors(page);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('./');

  await expect(page).toHaveTitle(/Cinder/);
  await expect(
    page.getByRole('heading', { name: /Build terminal UIs the Flutter way/i }),
  ).toBeVisible();
  await expect(page.getByText('CINDER RENDER PIPELINE').first()).toBeVisible();
  await expect(page.getByText('WEB RUNTIME AVAILABLE')).toBeVisible();
  await expect(page.locator('iframe[title*="rendered by Cinder"]')).toBeVisible();

  await page.screenshot({
    path: testInfo.outputPath('homepage-desktop.png'),
    fullPage: true,
    animations: 'disabled',
  });
  assertNoPageErrors();
});

test('documentation and generated example catalogue are reachable', async ({ page }) => {
  const assertNoPageErrors = failOnPageErrors(page);

  await page.goto('docs/');
  await expect(page.locator('main')).toContainText('Cinder');
  await expect(page.getByRole('link', { name: /Installation/i }).first()).toBeVisible();

  await page.goto('../examples/');
  await expect(page.getByRole('heading', { name: /Every example has an address/i })).toBeVisible();
  const search = page.getByPlaceholder('TextField, renderer, image…');
  await search.fill('web showcase');
  await expect(page.locator('.example-ledger')).toContainText('Web Showcase');
  assertNoPageErrors();
});

test('real Cinder web showcase boots, receives input, resizes, and restarts', async ({
  page,
}, testInfo) => {
  const assertNoPageErrors = failOnPageErrors(page);
  await page.goto('play/web-showcase/');

  const runtimeState = page.locator('.runtime-state');
  await expect(runtimeState).toHaveText('browser runtime', { timeout: 45_000 });

  const terminal = page.getByRole('application', {
    name: /Web Showcase terminal viewport/i,
  });
  await terminal.focus();
  await page.keyboard.press('Space');
  await page.setViewportSize({ width: 1024, height: 768 });
  await expect(runtimeState).toHaveText('browser runtime');

  await page.screenshot({
    path: testInfo.outputPath('web-showcase-runtime.png'),
    fullPage: true,
    animations: 'disabled',
  });

  await page.getByRole('button', { name: 'Restart' }).click();
  await expect(page.locator('.runtime-state')).toHaveText('browser runtime', {
    timeout: 45_000,
  });
  assertNoPageErrors();
});

test('native-only examples explain the missing browser capability', async ({ page }) => {
  const response = await page.request.get('generated/examples/manifest.json');
  expect(response.ok()).toBeTruthy();
  const manifest = (await response.json()) as ExampleManifest;
  const nativeExample = manifest.examples.find((example) => !example.runnable);

  test.skip(!nativeExample, 'The generated manifest contains no native-only example.');
  await page.goto(`examples/${nativeExample!.slug}/`);
  await expect(page.getByText('Native only').first()).toBeVisible();
  await expect(page.getByText(/not faked in the browser/i)).toBeVisible();
});

test('homepage remains usable at a mobile viewport', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('./');

  await expect(
    page.getByRole('heading', { name: /Build terminal UIs the Flutter way/i }),
  ).toBeVisible();
  await expect(page.getByRole('navigation', { name: 'Primary navigation' })).toBeVisible();
  await page.screenshot({
    path: testInfo.outputPath('homepage-mobile.png'),
    fullPage: true,
    animations: 'disabled',
  });
});
