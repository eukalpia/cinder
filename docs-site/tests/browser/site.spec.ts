import { expect, test, type Page } from '@playwright/test';

type RuntimeMode =
  | 'direct-web'
  | 'browser-adapter'
  | 'browser-sandbox'
  | 'native-only'
  | 'build-failed';

type ExampleManifest = {
  examples: Array<{
    slug: string;
    title: string;
    runnable: boolean;
    runtimeMode: RuntimeMode;
  }>;
};

type BrowserCinderBridge = {
  onInput: ((data: string) => void) | null;
};

function failOnPageErrors(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  return () => expect(errors, errors.join('\n')).toEqual([]);
}

async function loadManifest(page: Page) {
  const response = await page.request.get('generated/examples/manifest.json');
  expect(response.ok()).toBeTruthy();
  return (await response.json()) as ExampleManifest;
}

async function waitForRuntime(page: Page, title: RegExp) {
  const state = page.locator('.runtime-state');
  await expect(state).toHaveText('browser runtime', { timeout: 60_000 });
  const terminal = page.getByRole('application', { name: title });
  await expect(terminal).toHaveAttribute('data-guest-loaded', 'true');
  await expect
    .poll(async () => Number((await terminal.getAttribute('data-output-writes')) ?? '0'))
    .toBeGreaterThan(0);
  return terminal;
}

test('homepage presents Cinder as a terminal control surface', async ({
  page,
}, testInfo) => {
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
    path: testInfo.outputPath('homepage-1440x1000.png'),
    fullPage: true,
    animations: 'disabled',
  });
  assertNoPageErrors();
});

test('documentation and compatibility-aware catalogue are reachable', async ({
  page,
}) => {
  const assertNoPageErrors = failOnPageErrors(page);

  await page.goto('docs/');
  await expect(page.getByRole('heading', { name: 'What is Cinder?' })).toBeVisible();
  await expect(page.getByRole('link', { name: /Installation/i }).first()).toBeVisible();

  await page.goto('examples/');
  await expect(
    page.getByRole('heading', { name: /Every example has an address/i }),
  ).toBeVisible();
  const search = page.getByPlaceholder('TextField, renderer, image…');
  await search.fill('web showcase');
  await expect(page.locator('.example-ledger')).toContainText('Web Showcase');

  await search.clear();
  await page.getByRole('button', { name: 'Web adapter' }).click();
  await expect(page.locator('.example-ledger__row').first()).toBeVisible();
  await expect(page.locator('.compatibility--browser-adapter').first()).toBeVisible();
  assertNoPageErrors();
});

test('real Cinder runtime receives output, input, resize, and clean restart', async ({
  page,
}, testInfo) => {
  const assertNoPageErrors = failOnPageErrors(page);
  await page.goto('play/web-showcase/');

  const terminal = await waitForRuntime(
    page,
    /Web Showcase terminal viewport/i,
  );
  const inputBefore = Number(
    (await terminal.getAttribute('data-input-events')) ?? '0',
  );
  const resizeBefore = Number(
    (await terminal.getAttribute('data-resize-events')) ?? '0',
  );
  const geometryBefore = [
    await terminal.getAttribute('data-cols'),
    await terminal.getAttribute('data-rows'),
  ].join('x');

  await terminal.focus();
  await page.keyboard.press('Space');
  await expect
    .poll(async () => Number((await terminal.getAttribute('data-input-events')) ?? '0'))
    .toBeGreaterThan(inputBefore);

  await page.setViewportSize({ width: 1024, height: 768 });
  await expect
    .poll(async () => Number((await terminal.getAttribute('data-resize-events')) ?? '0'))
    .toBeGreaterThan(resizeBefore);
  await expect
    .poll(async () => {
      const geometry = [
        await terminal.getAttribute('data-cols'),
        await terminal.getAttribute('data-rows'),
      ].join('x');
      return geometry;
    })
    .not.toBe(geometryBefore);

  await page.screenshot({
    path: testInfo.outputPath('web-showcase-runtime.png'),
    fullPage: true,
    animations: 'disabled',
  });

  await page.getByRole('button', { name: 'Restart' }).click();
  await waitForRuntime(page, /Web Showcase terminal viewport/i);
  await expect(page.locator('script[data-cinder-guest]')).toHaveCount(1);
  assertNoPageErrors();
});

test('browser adapter and sandbox modes are disclosed and bootable', async ({
  page,
}) => {
  const manifest = await loadManifest(page);
  const adapted = manifest.examples.find(
    (example) =>
      example.runnable &&
      (example.runtimeMode === 'browser-adapter' ||
        example.runtimeMode === 'browser-sandbox'),
  );

  expect(adapted, 'Expected at least one generated adapter or sandbox.').toBeTruthy();
  await page.goto(`examples/${adapted!.slug}/`);
  await expect(
    page.locator(`.compatibility--${adapted!.runtimeMode}`),
  ).toBeVisible();
  await expect(page.getByText(/browser adapter|browser sandbox/i).first()).toBeVisible();

  await page.goto(`play/${adapted!.slug}/`);
  await waitForRuntime(
    page,
    new RegExp(`${escapeRegExp(adapted!.title)} terminal viewport`, 'i'),
  );
});

test('text input adapter accepts mixed Unicode through the Cinder bridge', async ({
  page,
}) => {
  const manifest = await loadManifest(page);
  const textField = manifest.examples.find(
    (example) => example.slug === 'textfield-demo' && example.runnable,
  );
  test.skip(!textField, 'The generated TextField adapter is not runnable.');

  await page.goto(`play/${textField!.slug}/`);
  const terminal = await waitForRuntime(
    page,
    /Textfield Demo terminal viewport/i,
  );
  const outputBefore = Number(
    (await terminal.getAttribute('data-output-writes')) ?? '0',
  );
  const sample = 'Привет 👋 مرحبا e\u0301';

  const bridgeReady = await page.evaluate(() => {
    const bridge = (window as typeof window & {
      cinderBridge?: BrowserCinderBridge;
    }).cinderBridge;
    return typeof bridge?.onInput === 'function';
  });
  expect(bridgeReady).toBeTruthy();

  await page.evaluate((value) => {
    const bridge = (window as typeof window & {
      cinderBridge?: BrowserCinderBridge;
    }).cinderBridge;
    bridge?.onInput?.(value);
    bridge?.onInput?.('\r');
  }, sample);

  await expect
    .poll(async () => Number((await terminal.getAttribute('data-output-writes')) ?? '0'))
    .toBeGreaterThan(outputBefore);
});

test('remaining native or failed examples explain the capability boundary', async ({
  page,
}) => {
  const manifest = await loadManifest(page);
  const sourceOnly = manifest.examples.find((example) => !example.runnable);
  test.skip(!sourceOnly, 'Every generated example is browser-runnable.');

  await page.goto(`examples/${sourceOnly!.slug}/`);
  await expect(
    page.locator(`.compatibility--${sourceOnly!.runtimeMode}`),
  ).toBeVisible();
  await expect(
    page.getByRole('heading', {
      name: /browser runner stops at the real boundary|browser build failed/i,
    }),
  ).toBeVisible();
});

test('responsive widths avoid document overflow and preserve navigation', async ({
  page,
}, testInfo) => {
  for (const viewport of [
    { width: 1024, height: 768, name: 'tablet-landscape' },
    { width: 768, height: 1024, name: 'tablet-portrait' },
    { width: 390, height: 844, name: 'mobile' },
    { width: 320, height: 700, name: 'mobile-narrow' },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto('./');
    await expect(
      page.getByRole('heading', { name: /Build terminal UIs the Flutter way/i }),
    ).toBeVisible();
    await expect(
      page.getByRole('navigation', { name: 'Primary navigation' }),
    ).toBeVisible();
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    expect(overflow, `${viewport.name} horizontal overflow`).toBeLessThanOrEqual(1);
    await page.screenshot({
      path: testInfo.outputPath(`homepage-${viewport.name}.png`),
      fullPage: true,
      animations: 'disabled',
    });
  }
});

test('keyboard navigation exposes the skip link and named frames', async ({ page }) => {
  await page.goto('./');
  const skipLink = page.getByRole('link', { name: 'Skip to content' });
  await page.keyboard.press('Tab');
  await expect(skipLink).toBeFocused();
  await skipLink.press('Enter');
  await expect(page.locator('#main-content')).toBeFocused();

  const frames = page.locator('iframe');
  const count = await frames.count();
  for (let index = 0; index < count; index++) {
    await expect(frames.nth(index)).toHaveAttribute('title', /\S+/);
  }

  const unnamedButtons = await page
    .locator('button')
    .evaluateAll((buttons) =>
      buttons.filter(
        (button) =>
          !button.textContent?.trim() &&
          !button.getAttribute('aria-label') &&
          !button.getAttribute('title'),
      ).length,
    );
  expect(unnamedButtons).toBe(0);
});

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
