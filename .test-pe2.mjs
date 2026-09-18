import puppeteer from 'puppeteer';
import { execSync } from 'child_process';

const chromePath = execSync("ls -d $HOME/.cache/puppeteer/chrome/*/chrome-mac-arm64/Google\\ Chrome\\ for\\ Testing.app/Contents/MacOS/Google\\ Chrome\\ for\\ Testing 2>/dev/null | tail -1").toString().trim();
const url = 'https://www.google.com/travel/flights?q=Flights+to+SFO+from+LHR+on+2026-04-17+one+way&curr=USD';

const browser = await puppeteer.launch({ headless: true, executablePath: chromePath });
const page = await browser.newPage();
await page.setViewport({ width: 1400, height: 2000 });
await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
await new Promise(r => setTimeout(r, 5000));

console.log('Step 1: Page loaded');

// Open dropdown
const opened = await page.evaluate(() => {
  const span = document.querySelector('[aria-label="Change seating class."]');
  if (!span) return 'no span';
  let el = span;
  while (el && el !== document.body) {
    if (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button' || el.getAttribute('jsaction')) {
      el.click();
      return 'clicked ' + el.tagName;
    }
    el = el.parentElement;
  }
  span.click();
  return 'clicked span';
});
console.log('Step 2: Dropdown -', opened);
await new Promise(r => setTimeout(r, 1500));
await page.screenshot({ path: '/tmp/gf-step2.png' });

// Click PE
const peClicked = await page.evaluate(() => {
  const lb = document.querySelector('[aria-label="Select your preferred seating class."]');
  if (!lb) return 'no listbox';
  const lis = [...lb.querySelectorAll('li')];
  for (const li of lis) {
    if (li.textContent.trim() === 'Premium economy') {
      li.click();
      return 'clicked';
    }
  }
  return 'not found';
});
console.log('Step 3: PE click -', peClicked);
await new Promise(r => setTimeout(r, 2000));
await page.screenshot({ path: '/tmp/gf-step3.png' });

// Click Done
await page.evaluate(() => {
  const btns = [...document.querySelectorAll('button')];
  const done = btns.find(b => b.textContent.trim() === 'Done');
  if (done) done.click();
});
console.log('Step 4: Clicked Done');
await new Promise(r => setTimeout(r, 8000));
await page.screenshot({ path: '/tmp/gf-step4.png' });

// Check results
const text = await page.evaluate(() => document.body.innerText);
const lines = text.split('\n').filter(l => l.trim());
console.log('Step 5: Page has', lines.length, 'lines');

const prices = text.match(/\$[\d,]+/g) || [];
console.log('Prices:', prices.slice(0, 8));

const hasTopFlights = text.includes('Top flights');
const hasOtherFlights = text.includes('Other flights');
console.log('Has Top flights:', hasTopFlights, 'Has Other flights:', hasOtherFlights);

// Check what AM/PM times exist
const times = lines.filter(l => l.match(/^\d{1,2}:\d{2}\s*[AP]M$/));
console.log('Times found:', times.slice(0, 5));

await browser.close();
