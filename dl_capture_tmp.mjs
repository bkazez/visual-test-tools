// Capture Delta flight-status XHR responses verbatim from a headless Chrome
// page load. Usage: node dl_capture.mjs URL OUTFILE [WAIT_SECONDS]
import puppeteer from 'puppeteer';
import fs from 'fs';
import os from 'os';
import path from 'path';

const [url, outFile, waitSec = '15'] = process.argv.slice(2);

const chromeDir = path.join(os.homedir(), '.cache/puppeteer/chrome');
const version = fs.readdirSync(chromeDir).sort().pop();
const chromePath = path.join(
  chromeDir, version,
  'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
);

const browser = await puppeteer.launch({
  headless: false,
  executablePath: chromePath,
  args: ['--disable-blink-features=AutomationControlled', '--window-position=2000,2000'],
  ignoreDefaultArgs: ['--enable-automation'],
});
const captures = [];
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900 });
  await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36');
  page.on('response', async (resp) => {
    const u = resp.url();
    if (u.includes('flightinformation-api.delta.com') || u.includes('flight-status')) {
      let body = '';
      try { body = await resp.text(); } catch (e) { body = 'UNREADABLE: ' + e.message; }
      captures.push({ url: u, status: resp.status(), method: resp.request().method(), postData: resp.request().postData() || null, body });
      console.error(`captured ${resp.status()} ${resp.request().method()} ${u} (${body.length} bytes)`);
    }
  });
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
    window.chrome = { runtime: {} };
  });
  const interact = async () => {
    for (let i = 0; i < 15; i++) {
      await page.mouse.move(120 + Math.random() * 900, 120 + Math.random() * 500, { steps: 8 });
      await new Promise((r) => setTimeout(r, 180 + Math.random() * 220));
    }
    await page.mouse.click(400, 300).catch(() => {});
    await page.keyboard.press('Tab').catch(() => {});
    await page.evaluate(() => window.scrollBy(0, 300 + Math.random() * 300)).catch(() => {});
  };
  const abckTail = async () => {
    const c = (await browser.cookies()).find((x) => x.name === '_abck');
    return c ? c.value.slice(-16) : 'MISSING';
  };
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });
  await interact();
  await new Promise((r) => setTimeout(r, 4000));
  console.error('_abck after load1: ' + (await abckTail()));
  // Akamai commonly validates only on a subsequent navigation carrying sensor data.
  await page.reload({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {});
  await interact();
  await new Promise((r) => setTimeout(r, 4000));
  console.error('_abck after load2: ' + (await abckTail()));
  await page.reload({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => {});
  await interact();
  await new Promise((r) => setTimeout(r, Number(waitSec) * 1000));
  console.error('_abck after load3: ' + (await abckTail()));
  // Retry the details POST in page context after the Akamai sensor has run.
  const postBody = process.env.DL_POST_BODY;
  if (postBody) {
    const result = await page.evaluate(async (b) => {
      const r = await fetch('https://flightinformation-api.delta.com/flight-status/details', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: b,
      }).catch((e) => null);
      if (!r) return { status: 0, body: 'fetch failed' };
      return { status: r.status, body: await r.text() };
    }, postBody);
    captures.push({ url: 'in-page-fetch', status: result.status, method: 'POST', postData: postBody, body: result.body });
    console.error(`in-page fetch: ${result.status} (${result.body.length} bytes)`);
  }
} catch (e) {
  console.error('Failed: ' + e.message);
} finally {
  await browser.close();
}
fs.writeFileSync(outFile, JSON.stringify(captures, null, 1));
console.error(`wrote ${captures.length} captures to ${outFile}`);
