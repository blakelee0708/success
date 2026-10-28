// Renders the launcher icon out of `icon.html`.
//
// **There is no image editor in this environment and no designer in the
// loop**, so the icon is a document that is rendered rather than a binary
// somebody drew once and nobody can change. Chromium and Playwright are
// pre-installed here, which is the same thing that let `site/privacy.html` be
// looked at rather than guessed about.
//
// Four files come out, because Android draws a launcher icon in two layers:
//
//  * `foreground.png` - the magnifier alone, transparent, scaled into the
//    **centre 66%**. Phones mask the icon to a circle, a squircle or a square
//    and the corners are not promised to anybody; art drawn to the edges is
//    art that gets cut on half the handsets.
//  * `background.png` - the white-to-grey ground, full bleed.
//  * `icon.png` - both layers flattened, for the legacy square and for Play.
//  * `preview.png` - the masks a phone actually applies at the sizes a phone
//    actually draws, which is the only way to see whether it reads at 48dp.
//
// **The fit is computed from the drawing's own numbers, not typed in.** The
// art's extent follows from `common` in `tube.js` - the ring's radius and
// wall, and where the handle ends - so changing the shape moves the scale with
// it instead of silently pushing the handle out of the safe zone.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const url = 'file://' + path.resolve(__dirname, 'icon.html');
const out = path.resolve(__dirname, '../../assets/icon');

const page = async (browser, size) => {
  const p = await browser.newPage({
    viewport: { width: size, height: size },
    deviceScaleFactor: 1,
  });
  await p.goto(url);
  await p.evaluate((s) => {
    const svg = document.getElementById('art');
    svg.setAttribute('width', s);
    svg.setAttribute('height', s);
  }, size);
  await p.waitForTimeout(250);
  return p;
};

// The visible extent of the art, ignoring the cast shadow - a soft shade that
// fades to nothing has no business deciding how big the magnifier is drawn.
const fit = (o) => {
  const k = 0.7071;
  const t = o.W * 0.92 / 2; // the handle's round cap
  const x0 = o.cx - o.R - o.W / 2;
  const y0 = o.cy - o.R - o.W / 2;
  const x1 = o.hx + t;
  const y1 = o.hy + t;
  const span = Math.max(x1 - x0, y1 - y0);
  const safe = 1024 * 0.66;
  const s = safe / span;
  return { s, mx: (x0 + x1) / 2, my: (y0 + y1) / 2, span, k };
};

(async () => {
  const browser = await chromium.launch();
  fs.mkdirSync(out, { recursive: true });

  // Foreground: the art alone, on nothing, inside the safe zone.
  let p = await page(browser, 1024);
  const f = await p.evaluate(() => {
    document.getElementById('bg').remove();
    return chosen;
  });
  const box = fit(f);
  await p.evaluate(
    (b) => document.getElementById('fg').setAttribute(
      'transform',
      `translate(512,512) scale(${b.s}) translate(${-b.mx},${-b.my})`,
    ),
    box,
  );
  await p.locator('#art').screenshot({
    path: path.join(out, 'foreground.png'),
    omitBackground: true,
  });
  await p.close();

  // Background: the ground alone, full bleed.
  p = await page(browser, 1024);
  await p.evaluate(() => document.getElementById('fg').remove());
  await p.locator('#art').screenshot({ path: path.join(out, 'background.png') });
  await p.close();

  // Flattened, for the legacy icon and for the Play listing. The art is left
  // at its drawn size here: nothing masks a legacy icon to a circle, so the
  // safe zone does not apply and shrinking it would waste the canvas.
  p = await page(browser, 1024);
  await p.locator('#art').screenshot({ path: path.join(out, 'icon.png') });
  await p.close();

  // The preview reads the three files that were just written.
  p = await browser.newPage({ viewport: { width: 980, height: 560 } });
  await p.goto('file://' + path.resolve(__dirname, 'preview.html'));
  await p.waitForTimeout(400);
  await p.screenshot({ path: path.join(__dirname, 'preview.png'), fullPage: true });
  await p.close();

  console.log(
    `fit: scale ${box.s.toFixed(3)} of a ${Math.round(box.span)}px drawing, ` +
    `centred on ${Math.round(box.mx)},${Math.round(box.my)}`,
  );
  await browser.close();
})();
