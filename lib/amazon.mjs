// Reads Amazon search results, product pages and reviews through headless Chrome.
//
// Amazon serves a logged-out visitor a generic international page: US dollars, no Prime
// badge, and a free-delivery date a week out. That page cannot answer "can this be here
// on Tuesday", which is usually the whole question. So before reading anything this sets
// the glow (Deliver to) postcode and the currency cookie, and re-checks that the ingress
// line actually changed -- the popover is flaky and silently no-ops if clicked too early.
//
// Env: AMZ_DOMAIN, AMZ_POSTCODE, AMZ_CURRENCY, AMZ_LOCALE, CHROME_PATH, CHROME_HEADLESS_JS.
import puppeteer from 'puppeteer';

const DOMAIN   = process.env.AMZ_DOMAIN   || 'www.amazon.co.uk';
const POSTCODE = process.env.AMZ_POSTCODE || '';
const CURRENCY = process.env.AMZ_CURRENCY || '';
const LOCALE   = process.env.AMZ_LOCALE   || 'en-GB,en;q=0.9';
const [mode, ...targets] = process.argv.slice(2);

const browser = await puppeteer.launch({
  headless: process.env.CHROME_HEADLESS_MODE === 'full' ? true : 'shell',
  executablePath: process.env.CHROME_PATH || undefined,
});
const page = await browser.newPage();
await page.setViewport({ width: 1400, height: 1200 });
await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36');
await page.setExtraHTTPHeaders({ 'Accept-Language': LOCALE });
if (CURRENCY) await browser.setCookie({ name: 'i18n-prefs', value: CURRENCY, domain: '.' + DOMAIN.replace(/^www\./, ''), path: '/' });

const sleep = ms => new Promise(r => setTimeout(r, ms));
const consent = async () => { try { await page.click('#sp-cc-accept'); await sleep(1200); } catch {} };
const go = async url => { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 }); await consent(); await sleep(2000); };

// The glow popover ignores clicks landing before its handler attaches, and gives no error.
async function setPostcode(pc) {
  await go(`https://${DOMAIN}/`);
  await page.waitForSelector('#nav-global-location-popover-link', { timeout: 30000 });
  await sleep(2500);
  for (let i = 0; i < 5; i++) {
    await page.click('#nav-global-location-popover-link');
    try { await page.waitForSelector('#GLUXZipUpdateInput', { timeout: 8000 }); break; } catch { await sleep(2000); }
  }
  await page.waitForSelector('#GLUXZipUpdateInput', { timeout: 8000 });
  await page.type('#GLUXZipUpdateInput', pc);
  await page.click('#GLUXZipUpdate input[type=submit], #GLUXZipUpdate');
  await sleep(2500);
  try { await page.click('#GLUXConfirmClose'); } catch {}
  await sleep(2500);
  await go(`https://${DOMAIN}/`);
  const line = await page.evaluate(() => document.querySelector('#glow-ingress-line2')?.innerText.trim() || '?');
  const key = pc.replace(/\s+/g, '').slice(0, 4).toUpperCase();
  if (!line.replace(/\s+/g, '').toUpperCase().includes(key)) throw new Error('ingress still reads "' + line + '"');
  return line;
}

if (POSTCODE) {
  let set = false;
  for (let a = 1; a <= 4 && !set; a++) {
    try { console.log('# delivery location: ' + await setPostcode(POSTCODE)); set = true; }
    catch (e) { console.error('# postcode attempt ' + a + ' failed: ' + e.message); }
  }
  if (!set) { console.error('# could not set postcode; delivery dates below are NOT trustworthy'); process.exitCode = 1; }
}

const text = (el, sel) => el.querySelector(sel)?.innerText.replace(/\s+/g, ' ').trim() || '';

for (const target of targets) {
  if (mode === 'search') {
    await go(`https://${DOMAIN}/s?k=` + encodeURIComponent(target));
    const items = await page.evaluate(() => {
      const t = (el, sel) => el.querySelector(sel)?.innerText.replace(/\s+/g, ' ').trim() || '';
      return [...document.querySelectorAll('[data-component-type="s-search-result"]')].map(el => {
        const txt = el.innerText.replace(/\s+/g, ' ');
        return {
          asin: el.getAttribute('data-asin'),
          title: t(el, 'h2'),
          price: t(el, '.a-price .a-offscreen'),
          rating: (txt.match(/([0-9.]+) out of 5 stars/) || [])[1] || '',
          reviews: (txt.match(/out of 5 stars ([0-9,]+)/) || [])[1] || '',
          delivery: [...txt.matchAll(/(?:FREE delivery|Or fastest delivery|Get it) [^|]{0,50}?(?= Or | Only | Add | \d+\+|$)/g)].map(m => m[0].trim()).join(' / '),
        };
      }).filter(i => i.asin);
    });
    console.log('### search: ' + target + ' (' + items.length + ' results)');
    for (const i of items) console.log(JSON.stringify(i));
  } else if (mode === 'product' || mode === 'reviews') {
    await go(`https://${DOMAIN}/dp/` + target);
    const d = await page.evaluate(mode => {
      const g = s => document.querySelector(s)?.innerText.replace(/\s+/g, ' ').trim() || '';
      const base = {
        asin: location.pathname.split('/dp/')[1]?.split('/')[0],
        title: g('#productTitle'),
        price: g('.a-price .a-offscreen') || g('#corePrice_feature_div'),
        availability: g('#availability'),
        delivery: g('#mir-layout-DELIVERY_BLOCK') || g('#deliveryBlockMessage'),
        rating: g('#acrPopover'), reviews: g('#acrCustomerReviewText'),
        brand: g('#bylineInfo'), merchant: g('#merchant-info') || g('#sellerProfileTriggerId'),
        image: document.querySelector('#landingImage')?.src || '',
      };
      if (mode === 'product') {
        base.bullets = [...document.querySelectorAll('#feature-bullets li')].map(e => e.innerText.replace(/\s+/g, ' ').trim());
        base.details = [...document.querySelectorAll('#productDetails_techSpec_section_1 tr, #detailBullets_feature_div li, #productOverview_feature_div tr')].map(e => e.innerText.replace(/\s+/g, ' ').trim());
      } else {
        base.reviewTexts = [...document.querySelectorAll('[data-hook="review"]')].map(e => e.innerText.replace(/\s+/g, ' ').trim());
      }
      return base;
    }, mode);
    console.log(JSON.stringify(d, null, 1));
  } else {
    console.error('Usage: amazon [search|product|reviews] TARGET...');
    process.exit(2);
  }
}
await browser.close();
