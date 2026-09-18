import puppeteer from 'puppeteer';

const browser = await puppeteer.launch({headless: 'new'});
const page = await browser.newPage();
await page.setViewport({width: 1440, height: 900});

// Login
await page.goto('http://localhost:3100/login', {waitUntil: 'networkidle0'});
await new Promise(r => setTimeout(r, 1000));
const inputs = await page.$$('input');
if (inputs.length >= 2) {
  await inputs[0].type('ben.kazez@gmail.com');
  await inputs[1].type('maestro0');
}
const button = await page.$('button[type="submit"]');
if (button) await button.click();
await page.waitForNavigation({waitUntil: 'networkidle0', timeout: 15000}).catch(() => {});

// Wait for strategy to appear
for (let i = 0; i < 40; i++) {
  await new Promise(r => setTimeout(r, 3000));
  const text = await page.evaluate(() => document.body.innerText);
  if (text.includes('Subject:') || text.includes('Dear ') || text.includes('Recommended')) break;
  if (i % 5 === 0) console.log('waiting...', i * 3, 's');
}

// Viewport screenshot only (not full page)
await page.screenshot({path: '/tmp/maestro_chat.png'});

// Extract the chat/strategy text
const allText = await page.evaluate(() => document.body.innerText);
// Find strategy-related content
const lines = allText.split('\n').filter(l => l.trim());
const strategyStart = lines.findIndex(l => l.includes('Strategy') || l.includes('Subject:') || l.includes('Dear '));
if (strategyStart >= 0) {
  console.log('=== STRATEGY/DRAFT ===');
  console.log(lines.slice(Math.max(0, strategyStart - 2), strategyStart + 20).join('\n'));
}

await browser.close();
