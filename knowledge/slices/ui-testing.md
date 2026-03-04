# OPNet Frontend UI Testing Reference

> **Role**: QA engineers and developers writing UI tests for OPNet React+Vite frontends
>
> **Self-contained**: All testing patterns, expected UI standards, and wallet mocking strategies are in this file.

---

## Expected UI Patterns

OPNet frontends follow strict design standards. Tests must verify these are met.

### Visual Standards to Verify

| Pattern | Expected | Rejection Trigger |
|---------|----------|-------------------|
| Background | Dark theme backgrounds | White or light backgrounds |
| Emojis | None anywhere in UI | Any emoji in text, buttons, or labels |
| Loading states | Skeleton loaders | Spinners or loading text |
| Card style | Glass-morphism (backdrop-blur, semi-transparent) | Flat opaque cards |
| Colors | CSS custom properties (--color-*) | Hardcoded hex/rgb values |
| Typography | Display font (NOT Inter/Roboto/Arial/system-ui) | System fonts for headings |
| Numbers | tabular-nums font-feature-settings | Proportional number rendering |
| Buttons | Hover + disabled states present | Missing interaction states |
| Backgrounds | Atmosphere (gradients, particles, or depth) | Flat single-color backgrounds |
| Reduced motion | `@media (prefers-reduced-motion)` query | No motion accessibility |

### Forbidden Visual Patterns

- Purple-to-blue gradient on white card ("AI slop")
- Spinners instead of skeleton loaders
- Flat backgrounds with no atmosphere
- Hardcoded colors instead of CSS custom properties

---

## Playwright Setup (Recommended)

Playwright is the recommended E2E testing framework for OPNet frontends. It supports multiple browsers, auto-waiting, and built-in screenshot/trace capture.

### Installation

```bash
cd frontend/
npm install -D @playwright/test
npx playwright install chromium  # Install browser binary
```

### Configuration (`playwright.config.ts`)

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests/e2e',
    timeout: 30_000,
    retries: 1,
    use: {
        baseURL: process.env.APP_URL ?? 'http://localhost:5173',
        headless: true,
        viewport: { width: 1440, height: 900 },
        screenshot: 'only-on-failure',
        trace: 'on-first-retry',
    },
    webServer: {
        command: 'npm run dev -- --port 5173',
        port: 5173,
        reuseExistingServer: true,
        timeout: 30_000,
    },
    outputDir: 'tests/e2e/results',
});
```

`★ Insight` -- Playwright's `webServer` config starts the dev server automatically and waits for it to be ready. No more fragile `sleep` or curl retry loops.

### Base Test Setup

```typescript
// tests/e2e/fixtures.ts
import { test as base, expect } from '@playwright/test';

export const test = base.extend({
    // Auto-inject wallet mock before every test
    page: async ({ page }, use) => {
        await page.addInitScript(() => {
            (window as Record<string, unknown>).__WALLET_MOCK__ = {
                isConnected: true,
                address: 'bc1p...testaddress',
                publicKey: '0x0203...mockedpubkey',
                hashedMLDSAKey: '0xABCD...mockedhashedkey',
                mldsaPublicKey: '0x...mockedmldsapubkey',
                network: { bech32: 'opt', pubKeyHash: 0x00, scriptHash: 0x05 },
            };
        });
        await use(page);
    },
});

export { expect };
```

---

## Wallet Mock Approach (WalletConnect v2)

OPNet frontends use WalletConnect v2 via `@btc-vision/walletconnect`. To test without a real wallet, mock the `useWalletConnect` hook.

### Mock Wallet Provider

```typescript
// tests/e2e/mocks/wallet-mock.ts
export const MOCK_WALLET = {
    isConnected: true,
    address: 'bc1p...testaddress',
    publicKey: '0x0203...mockedpubkey',
    hashedMLDSAKey: '0xABCD...mockedhashedkey',
    mldsaPublicKey: '0x...mockedmldsapubkey',
    network: { bech32: 'opt', pubKeyHash: 0x00, scriptHash: 0x05 },
    connectToWallet: async (): Promise<void> => {},
    disconnect: async (): Promise<void> => {},
};
```

### Injecting Mock via Playwright

```typescript
// Use addInitScript to inject before page loads (runs in browser context)
await page.addInitScript(() => {
    (window as Record<string, unknown>).__WALLET_MOCK__ = {
        isConnected: true,
        address: 'bc1p...testaddress',
        publicKey: '0x0203...mockedpubkey',
        hashedMLDSAKey: '0xABCD...mockedhashedkey',
    };
});

await page.goto('/');
```

In the application, check for the mock during testing:

```typescript
// In useWalletConnect wrapper or provider
const walletData = typeof window !== 'undefined' && (window as Record<string, unknown>).__WALLET_MOCK__
    ? (window as Record<string, unknown>).__WALLET_MOCK__ as WalletState
    : useWalletConnect();
```

---

## Smoke Test Checklist

Run these checks on every deployment candidate.

### 1. Page Load and Console Errors

```typescript
import { test, expect } from './fixtures';

test('page loads without console errors', async ({ page }) => {
    const errors: string[] = [];
    page.on('console', (msg) => {
        if (msg.type() === 'error') {
            errors.push(msg.text());
        }
    });

    const response = await page.goto('/');
    expect(response?.status()).toBe(200);

    // Filter out known acceptable warnings
    const realErrors = errors.filter(
        (e) => !e.includes('favicon') && !e.includes('DevTools')
    );
    expect(realErrors).toHaveLength(0);
});
```

### 2. Dark Theme Verification

```typescript
test('uses dark background', async ({ page }) => {
    await page.goto('/');

    const bgColor = await page.evaluate(() => {
        const body = document.querySelector('body');
        if (!body) return '';
        return getComputedStyle(body).backgroundColor;
    });

    // Parse RGB and check luminance is low (dark theme)
    const rgb = bgColor.match(/\d+/g)?.map(Number) ?? [255, 255, 255];
    const luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
    expect(luminance).toBeLessThan(0.3);
});
```

### 3. No Emojis in UI

```typescript
test('no emojis in visible text', async ({ page }) => {
    await page.goto('/');

    const hasEmoji = await page.evaluate(() => {
        const emojiPattern = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/u;
        return emojiPattern.test(document.body.innerText);
    });
    expect(hasEmoji).toBe(false);
});
```

### 4. CSS Custom Properties Used (No Hardcoded Colors)

```typescript
test('uses CSS custom properties for colors', async ({ page }) => {
    await page.goto('/');

    const hardcodedColors = await page.evaluate(() => {
        const sheets = Array.from(document.styleSheets);
        let hardcoded = 0;
        for (const sheet of sheets) {
            try {
                const rules = Array.from(sheet.cssRules);
                for (const rule of rules) {
                    if (rule instanceof CSSStyleRule) {
                        const style = rule.style;
                        for (let i = 0; i < style.length; i++) {
                            const prop = style.getPropertyValue(style[i]);
                            if (/#[0-9a-fA-F]{3,8}/.test(prop) && !rule.selectorText.includes(':root')) {
                                hardcoded++;
                            }
                        }
                    }
                }
            } catch {
                // Cross-origin stylesheets will throw
            }
        }
        return hardcoded;
    });
    expect(hardcodedColors).toBeLessThan(10);
});
```

### 5. Skeleton Loaders Present (No Spinners)

```typescript
test('uses skeleton loaders for loading states', async ({ page }) => {
    await page.goto('/');

    const spinnerPatterns = ['.spinner', '.loading-spinner', '[class*="spin"]', '.loader:not([class*="skeleton"])'];
    for (const selector of spinnerPatterns) {
        const count = await page.locator(selector).count();
        expect(count).toBe(0);
    }
});
```

### 6. Route Navigation

```typescript
test('all routes load without errors', async ({ page }) => {
    const routes = ['/', '/swap', '/tokens', '/portfolio']; // Adjust per project

    for (const route of routes) {
        const errors: string[] = [];
        page.on('console', (msg) => {
            if (msg.type() === 'error') errors.push(msg.text());
        });

        await page.goto(route);
        await page.waitForLoadState('networkidle');

        const realErrors = errors.filter(
            (e) => !e.includes('favicon') && !e.includes('DevTools')
        );
        expect(realErrors).toHaveLength(0);

        page.removeListener('console', () => {});
    }
});
```

### 7. Explorer Links Present

```typescript
test('transaction displays explorer links', async ({ page }) => {
    await page.goto('/');

    const links = await page.evaluate(() => {
        const anchors = Array.from(document.querySelectorAll('a[href]'));
        return anchors.map((a) => a.getAttribute('href')).filter(Boolean);
    });

    const hasMempoolLink = links.some((href) => href?.includes('mempool.opnet.org'));
    const hasOpscanLink = links.some((href) => href?.includes('opscan.org'));

    // These should be true after a tx is displayed
    if (links.length > 0) {
        expect(hasMempoolLink || hasOpscanLink).toBe(true);
    }
});
```

---

## E2E Test Patterns

### Mock Wallet Connect Flow

```typescript
test('wallet connect button triggers connection', async ({ page }) => {
    await page.goto('/');

    // Playwright auto-waits for elements
    const connectButton = page.locator('[data-testid="connect-wallet"], button:has-text("Connect")');
    await expect(connectButton).toBeVisible();

    await connectButton.click();

    // With mock wallet, should immediately show connected state
    await expect(
        page.locator('[data-testid="wallet-connected"], [data-testid="address-display"]')
    ).toBeVisible({ timeout: 5000 });
});
```

### Simulate Token Transfer Flow

```typescript
test('transfer flow: input -> simulate -> confirm', async ({ page }) => {
    await page.goto('/send');

    // Fill in recipient
    await page.locator('input[name="recipient"], [data-testid="recipient-input"]')
        .fill('bc1p...recipient');

    // Fill in amount
    await page.locator('input[name="amount"], [data-testid="amount-input"]')
        .fill('100');

    // Click send/transfer
    await page.locator('[data-testid="send-button"], button:has-text("Send")').click();

    // Verify confirmation dialog or tx status appears
    await expect(
        page.locator('[data-testid="tx-status"], [data-testid="confirm-dialog"]')
    ).toBeVisible({ timeout: 10_000 });
});
```

### Verify Transaction Status Display

```typescript
test('tx status shows mempool and opscan links', async ({ page }) => {
    // After submitting a tx (with mock), check the status display
    const txStatus = page.locator('[data-testid="tx-status"]');
    await expect(txStatus).toBeVisible();

    // Must contain both explorer links
    await expect(txStatus).toContainText('mempool.opnet.org');
    await expect(txStatus).toContainText('opscan.org');
});
```

---

## Responsive Breakpoint Testing

```typescript
const breakpoints = [
    { name: 'mobile', width: 375, height: 812 },
    { name: 'tablet', width: 768, height: 1024 },
    { name: 'desktop', width: 1440, height: 900 },
] as const;

for (const bp of breakpoints) {
    test(`renders correctly at ${bp.name} (${bp.width}x${bp.height})`, async ({ page }) => {
        await page.setViewportSize({ width: bp.width, height: bp.height });
        await page.goto('/');
        await page.waitForLoadState('networkidle');

        // No horizontal overflow
        const hasOverflow = await page.evaluate(() => {
            return document.documentElement.scrollWidth > document.documentElement.clientWidth;
        });
        expect(hasOverflow).toBe(false);

        // Key elements visible
        await expect(
            page.locator('main, [data-testid="app-content"], #root > div')
        ).toBeVisible();
    });
}
```

---

## Visual Regression Testing

Playwright has built-in visual comparison:

```typescript
test('homepage matches visual snapshot', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Compare against baseline screenshot
    await expect(page).toHaveScreenshot('homepage.png', {
        maxDiffPixels: 100,  // Allow minor rendering differences
    });
});

test('dark theme snapshot at mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');

    await expect(page).toHaveScreenshot('homepage-mobile.png', {
        maxDiffPixels: 50,
    });
});
```

Update baselines with: `npx playwright test --update-snapshots`

---

## Accessibility Testing

```typescript
test('reduced-motion media query exists', async ({ page }) => {
    await page.goto('/');

    const hasReducedMotion = await page.evaluate(() => {
        const sheets = Array.from(document.styleSheets);
        for (const sheet of sheets) {
            try {
                const rules = Array.from(sheet.cssRules);
                for (const rule of rules) {
                    if (rule instanceof CSSMediaRule && rule.conditionText.includes('prefers-reduced-motion')) {
                        return true;
                    }
                }
            } catch {
                // Cross-origin
            }
        }
        return false;
    });
    expect(hasReducedMotion).toBe(true);
});
```

### Emulate Reduced Motion

```typescript
test('animations disabled with reduced-motion', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/');

    // Verify no active CSS animations
    const animations = await page.evaluate(() => {
        return document.getAnimations().length;
    });
    expect(animations).toBe(0);
});
```

---

## Running Tests

```bash
# Run all E2E tests
npx playwright test

# Run with visible browser (debugging)
npx playwright test --headed

# Run specific test file
npx playwright test tests/e2e/smoke.spec.ts

# Generate HTML report
npx playwright test --reporter=html

# View trace for failed tests
npx playwright show-trace tests/e2e/results/trace.zip
```

---

## Dogfooding: Test the Plugin Itself

When developing the buidl plugin, use these patterns to validate the UI tester agent's output:

1. **Run the UI tester agent against a known-good frontend** -- verify it passes all smoke tests
2. **Introduce intentional regressions** (add a spinner, use white background, add emoji) and verify the UI tester catches them
3. **Check screenshot output** -- every failure should have visual evidence in `tests/e2e/screenshots/`
4. **Validate results.json** -- confirm the structure matches the expected format (status, tests breakdown, screenshots array)
5. **Test wallet mock injection** -- verify the mock correctly overrides `useWalletConnect` behavior
