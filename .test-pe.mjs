import puppeteer from 'puppeteer';
import { execSync } from 'child_process';

const chromePath = execSync("ls -d $HOME/.cache/puppeteer/chrome/*/chrome-mac-arm64/Google\\ Chrome\\ for\\ Testing.app/Contents/MacOS/Google\\ Chrome\\ for\\ Testing 2>/dev/null | tail -1").toString().trim();
const url = 'https://www.google.com/travel/flights?q=Flights+to+SFO+from+LHR+on+2026-04-17+one+way&curr=USD';

const browser = await puppeteer.launch({ headless: true, executablePath: chromePath });
const page = await browser.newPage();
await page.setViewport({ width: 1400, height: 900 });
await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
await new Promise(r => setTimeout(r, 5000));

// Find and click the cabin class dropdown via JS click on nearest clickable ancestor
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
  return 'clicked span directly';
});
console.log('Dropdown open:', opened);
await new Promise(r => setTimeout(r, 1500));

// Check listbox visibility
const listboxInfo = await page.evaluate(() => {
  const lb = document.querySelector('[aria-label="Select your preferred seating class."]');
  if (!lb) return 'no listbox';
  const lis = [...lb.querySelectorAll('li')];
  return 'items: ' + lis.map(l => l.textContent.trim() + ' (selected:' + l.getAttribute('aria-selected') + ')').join(', ');
});
console.log('Listbox:', listboxInfo);

// Click Premium economy
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
  return 'not found among: ' + lis.map(l => l.textContent.trim()).join(', ');
});
console.log('Premium economy:', peClicked);
await new Promise(r => setTimeout(r, 3000));

// Look for Search button
const searchResult = await page.evaluate(() => {
  const btns = [...document.querySelectorAll('button')];
  const texts = btns.map(b => b.textContent.trim().substring(0, 30));
  const s = btns.find(b => /^Search$/.test(b.textContent.trim()));
  if (s) { s.click(); return 'clicked search'; }
  return 'no search button. buttons: ' + texts.filter(t => t.length > 0 && t.length < 20).join(', ');
});
console.log('Search:', searchResult);
await new Promise(r => setTimeout(r, 8000));

// Get prices
const prices = await page.evaluate(() => {
  const text = document.body.innerText;
  const matches = text.match(/\$[\d,]+/g);
  return matches ? matches.slice(0, 10) : [];
});
console.log('Prices:', prices);

await browser.close();
