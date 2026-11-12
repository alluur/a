// Renders brand/cover.html to brand/cover.png (1600 x 2560) with Chromium. Not part of the normal build: the PNG is committed.
//   node docs/book/tools/cover.js        (needs the playwright package)
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const brand = path.join(__dirname, '..', 'brand');
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 2560 }, deviceScaleFactor: 1 });
  await p.goto('file://' + path.join(brand, 'cover.html'));
  await p.waitForTimeout(500);
  await p.screenshot({ path: path.join(brand, 'cover.png') });
  await b.close();
  console.log('wrote', path.join(brand, 'cover.png'));
})();
