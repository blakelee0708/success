// The magnifier, drawn as a tube.
//
// **One source for the shape**, shared by the gallery that chose it and by
// the build that renders the launcher icon. Two copies of a drawing is two
// drawings, and the one nobody is looking at is the one that drifts.
//
// The reference was a 3D render: the ring is a fat doughnut whose
// cross-section is round, so a narrow band of light runs *along* the tube and
// the far side falls away into shade. A flat stroke with a drop shadow cannot
// do that however thick it is, which is what four earlier attempts were.
//
// **Everything that makes the roundness is masked to the tube itself.** The
// first version let the highlight bleed over the lens edge and past the rim,
// and the ring came out a ball rather than a doughnut - the hole is what says
// torus, so nothing may soften its edge.
//
// Every id carries the variant's own suffix, because these SVGs sit in one
// document and a gradient id resolves across all of them: three icons once
// shared a background and came out the same colour.
const ring = (o) => {
  const { cx, cy, R, W, id } = o;
  // The circle path starts at 3 o'clock and runs clockwise, so with
  // pathLength=100 the quarters are 0-25 down, 25-50 left, 50-75 up and
  // 75-100 back. The lit arc is the upper left, 50..77.
  return `
  <mask id="tube${id}">
    <circle cx="${cx}" cy="${cy}" r="${R}" fill="none"
            stroke="#fff" stroke-width="${W}"/>
  </mask>
  <g mask="url(#tube${id})">
    <circle cx="${cx}" cy="${cy}" r="${R}" fill="none"
            stroke="url(#face${id})" stroke-width="${W}"/>
    <g filter="url(#soft${id})">
      <circle cx="${cx}" cy="${cy}" r="${R + W * 0.30}" fill="none"
              stroke="${o.deep}" stroke-width="${W * 0.52}" opacity=".9"
              pathLength="100" stroke-dasharray="34 66" stroke-dashoffset="-2"
              stroke-linecap="round"/>
      <circle cx="${cx}" cy="${cy}" r="${R - W * 0.34}" fill="none"
              stroke="${o.deep}" stroke-width="${W * 0.34}" opacity=".55"
              pathLength="100" stroke-dasharray="30 70" stroke-dashoffset="-6"
              stroke-linecap="round"/>
    </g>
    <g filter="url(#tight${id})">
      <circle cx="${cx}" cy="${cy}" r="${R - W * 0.16}" fill="none"
              stroke="${o.lit}" stroke-width="${W * 0.24}" opacity=".98"
              pathLength="100" stroke-dasharray="24 76" stroke-dashoffset="-51"
              stroke-linecap="round"/>
      <circle cx="${cx}" cy="${cy}" r="${R + W * 0.28}" fill="none"
              stroke="${o.lit}" stroke-width="${W * 0.16}" opacity=".5"
              pathLength="100" stroke-dasharray="14 86" stroke-dashoffset="-33"
              stroke-linecap="round"/>
    </g>
  </g>`;
};

const handle = (o) => {
  const { cx, cy, R, W, id } = o;
  const k = 0.7071;
  const x1 = cx + R * k, y1 = cy + R * k;
  const t = W * 0.92;
  return `
  <mask id="grip${id}">
    <line x1="${x1}" y1="${y1}" x2="${o.hx}" y2="${o.hy}"
          stroke="#fff" stroke-width="${t}" stroke-linecap="round"/>
  </mask>
  <g mask="url(#grip${id})">
    <line x1="${x1}" y1="${y1}" x2="${o.hx}" y2="${o.hy}"
          stroke="url(#gripF${id})" stroke-width="${t}" stroke-linecap="round"/>
    <g filter="url(#tight${id})">
      <line x1="${x1 + 20}" y1="${y1 - 20}" x2="${o.hx + 14}" y2="${o.hy - 14}"
            stroke="${o.gripLit}" stroke-width="${t * 0.2}" opacity=".95"
            stroke-linecap="round"/>
      <line x1="${x1 - 26}" y1="${y1 + 26}" x2="${o.hx - 18}" y2="${o.hy + 18}"
            stroke="${o.gripDeep}" stroke-width="${t * 0.34}" opacity=".85"
            stroke-linecap="round"/>
    </g>
  </g>`;
};

// The hole. Its edge has to stay crisp - it is the only thing that says
// doughnut rather than ball - so the shadow the tube casts into it is masked
// to the hole as tightly as the tube's own light is masked to the tube.
const lens = (o) => {
  const r = o.R - o.W / 2 + 2;
  return `
  <mask id="hole${o.id}">
    <circle cx="${o.cx}" cy="${o.cy}" r="${r}" fill="#fff"/>
  </mask>
  <g mask="url(#hole${o.id})">
    <circle cx="${o.cx}" cy="${o.cy}" r="${r}" fill="url(#glass${o.id})"/>
    <g filter="url(#soft${o.id})">
      <circle cx="${o.cx}" cy="${o.cy}" r="${r - 10}" fill="none"
              stroke="${o.deep}" stroke-width="40" opacity=".26"
              pathLength="100" stroke-dasharray="36 64" stroke-dashoffset="-46"
              stroke-linecap="round"/>
    </g>
  </g>`;
};

const defs = (o) => `
 <defs>
  <linearGradient id="face${o.id}" x1=".1" y1="0" x2=".9" y2="1">
    <stop offset="0" stop-color="${o.lit}"/>
    <stop offset=".45" stop-color="${o.base}"/>
    <stop offset="1" stop-color="${o.deep}"/>
  </linearGradient>
  <linearGradient id="gripF${o.id}" x1=".25" y1="0" x2=".75" y2="1">
    <stop offset="0" stop-color="${o.gripLit}"/>
    <stop offset=".45" stop-color="${o.grip}"/>
    <stop offset="1" stop-color="${o.gripDeep}"/>
  </linearGradient>
  <radialGradient id="glass${o.id}" cx="40%" cy="32%" r="80%">
    <stop offset="0" stop-color="${o.glassLit}"/>
    <stop offset="1" stop-color="${o.glass}"/>
  </radialGradient>
  <linearGradient id="bg${o.id}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${o.bgLit}"/>
    <stop offset="1" stop-color="${o.bg}"/>
  </linearGradient>
  <filter id="soft${o.id}" x="-45%" y="-45%" width="190%" height="190%">
    <feGaussianBlur stdDeviation="20"/></filter>
  <filter id="tight${o.id}" x="-45%" y="-45%" width="190%" height="190%">
    <feGaussianBlur stdDeviation="9"/></filter>
  <filter id="cast${o.id}" x="-50%" y="-50%" width="200%" height="200%">
    <feDropShadow dx="0" dy="24" stdDeviation="24"
                  flood-color="${o.castColor}" flood-opacity=".3"/></filter>
 </defs>`;

const build = (o) => `${defs(o)}
  <rect width="1024" height="1024" fill="url(#bg${o.id})"/>
  <g filter="url(#cast${o.id})">
    ${handle(o)}
    ${lens(o)}
    ${ring(o)}
  </g>
  <text x="${o.cx}" y="${o.cy + 4}" font-size="${o.glyph}" fill="${o.ink}"
        text-anchor="middle" dominant-baseline="central">잘</text>`;

const common = { cx: 424, cy: 406, R: 244, W: 112, hx: 858, hy: 840, glyph: 248 };

// **The amber is gone.** Terracotta sits at 13 degrees, the amber at 32 and
// the cream between them, so three warm oranges were competing and none of
// them won - the same thing this repository already recorded about the warm
// band on the home screen, where anything fitted between those hues is
// indistinguishable at arm's length. The reference reads because it is two
// *different* hues on white.
//
// So: one strong colour, and the second is either a neutral or a hue far
// enough away to be a different colour rather than a shade of the first.
