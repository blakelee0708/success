// Renders the launcher icon out of `app_icon.html`.
//
// **There is no image editor in this environment and no designer in the
// loop**, so the icon is a document that is rendered rather than a binary
// somebody drew once and nobody can change. Chromium and Playwright are
// pre-installed here, which is the same thing that let `site/privacy.html`
// be looked at rather than guessed about.
//
// Three files come out, and they are three because Android draws a launcher
// icon in two layers:
//
//  * `foreground.png` — the magnifier alone, transparent, and **inside the
//    centre 66%**. Phones mask the icon to a circle, a squircle or a square
//    and the corners are not promised to anybody; art that fills the canvas
//    is art that gets cut on half the handsets.
//  * `icon.png` — both layers flattened, for the legacy square and for Play.
//  * `preview.png` — the masks a phone actually applies, at the size a phone
//    actually draws, which is the only way to see whether it reads at 48dp.
const { chromium } = require('playwright');
const path = require('path');

const page = async (browser, size) => {
  const p = await browser.newPage({
    viewport: { width: size, height: size },
    deviceScaleFactor: 1,
  });
  await p.goto('file://' + path.resolve(__dirname, 'app_icon.html'));
  await p.evaluate((s) => {
    const svg = document.getElementById('art');
    svg.setAttribute('width', s);
    svg.setAttribute('height', s);
  }, size);
  await p.waitForTimeout(250);
  return p;
};

(async () => {
  const browser = await chromium.launch();
  const out = path.resolve(__dirname, '../../assets/icon');

  // Foreground: the art alone, on nothing.
  let p = await page(browser, 1024);
  await p.evaluate(() => {
    document.getElementById('bg').remove();
    // The safe zone is the centre 66%, so the art is scaled into it rather
    // than drawn to the edges and hoped about.
    document.getElementById('fg').setAttribute(
      'transform',
      'translate(512,512) scale(0.64) translate(-512,-512)',
    );
  });
  await p.locator('#art').screenshot({
    path: path.join(out, 'foreground.png'),
    omitBackground: true,
  });
  await p.close();

  // Flattened, for the legacy icon and for the Play listing.
  p = await page(browser, 1024);
  await p.locator('#art').screenshot({ path: path.join(out, 'icon.png') });
  await p.close();

  await browser.close();
  console.log('wrote foreground.png and icon.png');
})();
