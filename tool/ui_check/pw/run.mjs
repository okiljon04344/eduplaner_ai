// Usage: node run.mjs <profile> <width> <height> '<json steps>'
// Steps: ["goto", path] ["wait", ms] ["click", x, y] ["type", text] ["key", k]
//        ["shot", name] ["text"] (dumps semantics labels) ["clear"] (wipe storage)
import { createRequire } from 'node:module';
const require = createRequire('/home/yashiloyceo/.npm/_npx/9833c18b2d85bc59/node_modules/');
const { chromium } = require('playwright');

const [profile, w, h, stepsJson] = process.argv.slice(2);
const OUT = new URL('../shots/', import.meta.url).pathname;
const BASE = 'http://127.0.0.1:8098';
const ctx = await chromium.launchPersistentContext(new URL(`../profiles/${profile}`, import.meta.url).pathname, {
  executablePath: '/usr/bin/google-chrome',
  headless: true,
  viewport: { width: Number(w), height: Number(h) },
  deviceScaleFactor: 1,
  colorScheme: process.env.COLOR || 'light',
  isMobile: Number(w) < 600,
  hasTouch: Number(w) < 600,
});
const page = ctx.pages()[0] ?? await ctx.newPage();
await ctx.addInitScript(() => { Error.stackTraceLimit = 200; });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' || (process.env.LOGALL && true)) errors.push(m.type() + ': ' + m.text().slice(0, 3000)); });
page.on('pageerror', (e) => errors.push(String(e).slice(0, 200)));

for (const [op, a, b] of JSON.parse(stepsJson)) {
  if (op === 'goto') await page.goto(BASE + a, { waitUntil: 'load' });
  else if (op === 'wait') await page.waitForTimeout(a);
  else if (op === 'nav') await page.evaluate((u) => { location.hash = u; }, a);
  else if (op === 'login') {
    // a = email; full sign-in without reloads (emulator sessions do not survive a reload)
    const f = b;
    for (let attempt = 0; attempt < 3; attempt++) {
      await page.goto(BASE + '/', { waitUntil: 'load' });
      await page.waitForTimeout(4500);
      await page.mouse.click(f[6], f[7]); await page.waitForTimeout(1800);
      await page.mouse.click(f[4], f[5]); await page.waitForTimeout(1800);
      await page.mouse.click(f[0], f[1]); await page.waitForTimeout(400);
      await page.keyboard.type(a, { delay: 15 });
      await page.mouse.click(f[2], f[3]); await page.waitForTimeout(400);
      await page.keyboard.type('test-pass-123', { delay: 15 });
      await page.mouse.click(10, 200); await page.waitForTimeout(500);
      await page.mouse.click(f[8], f[9]);
      for (let i = 0; i < 12 && !/home|onboarding|profile/.test(page.url()); i++) await page.waitForTimeout(1000);
      if (/home|onboarding|profile/.test(page.url())) break;
    }
    await page.waitForTimeout(2000);
    await page.addStyleTag({ content: '.firebase-emulator-warning{display:none!important}' });
    console.log('after login:', page.url());
  }
  else if (op === 'click') await page.mouse.click(a, b);
  else if (op === 'resize') { await page.setViewportSize({ width: a, height: b }); await page.waitForTimeout(1500); }
  else if (op === 'type') await page.keyboard.type(a, { delay: 20 });
  else if (op === 'key') await page.keyboard.press(a);
  else if (op === 'shot') await page.screenshot({ path: `${OUT}${a}.png` });
  else if (op === 'scroll') { await page.mouse.move(Number(w) / 2, Number(h) / 2); await page.mouse.wheel(0, a); }
  else if (op === 'clear') {
    await page.goto(BASE + '/', { waitUntil: 'load' });
    await page.evaluate(async () => {
      for (const d of await indexedDB.databases()) indexedDB.deleteDatabase(d.name);
      localStorage.clear();
    });
  } else if (op === 'text') {
    const labels = await page.evaluate(() => {
      document.querySelector('flt-semantics-placeholder')?.click();
      return [...document.querySelectorAll('flt-semantics [aria-label], flt-semantics span, flt-semantics')]
        .map((e) => {
          const r = e.getBoundingClientRect();
          const t = (e.getAttribute('aria-label') || e.textContent || '').trim();
          return t && r.width ? `${Math.round(r.x + r.width / 2)},${Math.round(r.y + r.height / 2)} ${e.getAttribute('role') || ''} ${t.slice(0, 60)}` : null;
        })
        .filter(Boolean);
    });
    console.log([...new Set(labels)].join('\n'));
  }
}
if (errors.length) console.log('CONSOLE ERRORS:\n' + [...new Set(errors)].join('\n'));
await ctx.close();
