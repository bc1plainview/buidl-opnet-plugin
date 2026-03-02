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

## Puppeteer-Based Testing Setup

```typescript
import puppeteer, { Browser, Page } from 'puppeteer';

let browser: Browser;
let page: Page;

const APP_URL = process.env.APP_URL ?? 'http://localhost:5173';

beforeAll(async () => {
    browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });
    page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
});

afterAll(async () => {
    await browser.close();
});
```

---

## Wallet Mock Approach (WalletConnect v2)

OPNet frontends use WalletConnect v2 via `@btc-vision/walletconnect`. To test without a real wallet, mock the `useWalletConnect` hook.

### Mock Wallet Provider

```typescript
// test/mocks/wallet-mock.ts
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

### Injecting Mock into Page

```typescript
// Before navigating, inject mock into window
await page.evaluateOnNewDocument(() => {
    (window as Record<string, unknown>).__WALLET_MOCK__ = {
        isConnected: true,
        address: 'bc1p...testaddress',
        publicKey: '0x0203...mockedpubkey',
        hashedMLDSAKey: '0xABCD...mockedhashedkey',
    };
});

await page.goto(APP_URL);
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
test('page loads without console errors', async () => {
    const errors: string[] = [];
    page.on('console', (msg) => {
        if (msg.type() === 'error') {
            errors.push(msg.text());
        }
    });

    const response = await page.goto(APP_URL, { waitUntil: 'networkidle0' });
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
test('uses dark background', async () => {
    const bgColor = await page.evaluate(() => {
        const body = document.querySelector('body');
        if (!body) return '';
        return getComputedStyle(body).backgroundColor;
    });

    // Parse RGB and check luminance is low (dark theme)
    const rgb = bgColor.match(/\d+/g)?.map(Number) ?? [255, 255, 255];
    const luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
    expect(luminance).toBeLessThan(0.3); // Dark background
});
```

### 3. No Emojis in UI

```typescript
test('no emojis in visible text', async () => {
    const hasEmoji = await page.evaluate(() => {
        const emojiPattern = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/u;
        const textContent = document.body.innerText;
        return emojiPattern.test(textContent);
    });
    expect(hasEmoji).toBe(false);
});
```

### 4. CSS Custom Properties Used (No Hardcoded Colors)

```typescript
test('uses CSS custom properties for colors', async () => {
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
                            // Check for hardcoded hex colors (not in :root or custom properties)
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
    // Allow some hardcoded colors but flag excessive use
    expect(hardcodedColors).toBeLessThan(10);
});
```

### 5. Skeleton Loaders Present (No Spinners)

```typescript
test('uses skeleton loaders for loading states', async () => {
    const hasSpinner = await page.evaluate(() => {
        const spinnerPatterns = ['.spinner', '.loading-spinner', '[class*="spin"]', '.loader:not([class*="skeleton"])'];
        return spinnerPatterns.some((selector) => document.querySelector(selector) !== null);
    });
    expect(hasSpinner).toBe(false);
});
```

### 6. Route Navigation

```typescript
test('all routes load without errors', async () => {
    const routes = ['/', '/swap', '/tokens', '/portfolio']; // Adjust per project

    for (const route of routes) {
        const errors: string[] = [];
        page.on('console', (msg) => {
            if (msg.type() === 'error') errors.push(msg.text());
        });

        await page.goto(`${APP_URL}${route}`, { waitUntil: 'networkidle0' });

        const realErrors = errors.filter(
            (e) => !e.includes('favicon') && !e.includes('DevTools')
        );
        expect(realErrors).toHaveLength(0);

        page.removeAllListeners('console');
    }
});
```

### 7. Explorer Links Present

```typescript
test('transaction displays explorer links', async () => {
    // After a mock transaction, verify both explorer links are shown
    const links = await page.evaluate(() => {
        const anchors = Array.from(document.querySelectorAll('a[href]'));
        return anchors.map((a) => a.getAttribute('href')).filter(Boolean);
    });

    const hasMempoolLink = links.some((href) =>
        href?.includes('mempool.opnet.org')
    );
    const hasOpscanLink = links.some((href) =>
        href?.includes('opscan.org')
    );

    // These should be true after a tx is displayed
    // If no tx has been made yet, this test is informational
    if (links.length > 0) {
        expect(hasMempoolLink || hasOpscanLink).toBe(true);
    }
});
```

---

## E2E Test Patterns

### Mock Wallet Connect Flow

```typescript
test('wallet connect button triggers connection', async () => {
    // Look for connect button
    const connectButton = await page.waitForSelector('[data-testid="connect-wallet"], button:has-text("Connect")');
    expect(connectButton).not.toBeNull();

    // Click and verify state change
    await connectButton?.click();

    // With mock wallet, should immediately show connected state
    await page.waitForSelector('[data-testid="wallet-connected"], [data-testid="address-display"]', {
        timeout: 5000,
    });
});
```

### Simulate Token Transfer Flow

```typescript
test('transfer flow: input -> simulate -> confirm', async () => {
    // 1. Navigate to transfer/send page
    await page.goto(`${APP_URL}/send`);

    // 2. Fill in recipient
    const recipientInput = await page.waitForSelector('input[name="recipient"], [data-testid="recipient-input"]');
    await recipientInput?.type('bc1p...recipient');

    // 3. Fill in amount
    const amountInput = await page.waitForSelector('input[name="amount"], [data-testid="amount-input"]');
    await amountInput?.type('100');

    // 4. Click send/transfer
    const sendButton = await page.waitForSelector('[data-testid="send-button"], button:has-text("Send")');
    await sendButton?.click();

    // 5. Verify confirmation dialog or tx status appears
    const confirmation = await page.waitForSelector('[data-testid="tx-status"], [data-testid="confirm-dialog"]', {
        timeout: 10000,
    });
    expect(confirmation).not.toBeNull();
});
```

### Verify Transaction Status Display

```typescript
test('tx status shows mempool and opscan links', async () => {
    // After submitting a tx (with mock), check the status display
    const txStatus = await page.waitForSelector('[data-testid="tx-status"]');

    const statusHTML = await txStatus?.evaluate((el) => el.innerHTML);

    // Must contain both explorer links
    expect(statusHTML).toContain('mempool.opnet.org');
    expect(statusHTML).toContain('opscan.org');
});
```

---

## Responsive Breakpoint Testing

```typescript
const breakpoints = [
    { name: 'mobile', width: 375, height: 812 },
    { name: 'tablet', width: 768, height: 1024 },
    { name: 'desktop', width: 1440, height: 900 },
];

for (const bp of breakpoints) {
    test(`renders correctly at ${bp.name} (${bp.width}x${bp.height})`, async () => {
        await page.setViewport({ width: bp.width, height: bp.height });
        await page.goto(APP_URL, { waitUntil: 'networkidle0' });

        // No horizontal overflow
        const hasOverflow = await page.evaluate(() => {
            return document.documentElement.scrollWidth > document.documentElement.clientWidth;
        });
        expect(hasOverflow).toBe(false);

        // Key elements visible
        const mainContent = await page.$('main, [data-testid="app-content"], #root > div');
        expect(mainContent).not.toBeNull();
    });
}
```

---

## Accessibility Testing

```typescript
test('reduced-motion media query exists', async () => {
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
