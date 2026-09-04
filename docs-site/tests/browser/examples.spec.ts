import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';

const manifest = JSON.parse(
  readFileSync('out/generated/examples/manifest.json', 'utf8'),
) as {
  examples: Array<{ slug: string; runnable: boolean; runtimeMode: string }>;
};

test('official example compilation has no failures', () => {
  expect(
    manifest.examples.filter((example) => example.runtimeMode === 'build-failed'),
  ).toEqual([]);
});

for (const example of manifest.examples.filter((example) => example.runnable)) {
  test(`${example.slug} produces Cinder terminal output without runtime errors`, async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(`play/${example.slug}/`);
    const terminal = page.locator('[data-guest-loaded]');
    await expect(terminal).toHaveAttribute('data-guest-loaded', 'true');
    await expect
      .poll(async () => Number(await terminal.getAttribute('data-output-writes')))
      .toBeGreaterThan(0);
    if (example.slug === 'paste-verification') {
      await expect(terminal).toContainText('SUCCESS: Terminal paste works correctly!');
    }
    if (example.slug === 'test-sparkles-width') {
      await expect(terminal).toContainText('Sparkles emoji');
      await expect(terminal).toContainText('Our width calculation: 2');
    }
    expect(errors).toEqual([]);
  });
}
