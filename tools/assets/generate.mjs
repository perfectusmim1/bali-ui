// Bali UI asset generator
// Renders a Lucide icon atlas plus procedural glass assets (glow, shadow, grain)
// and emits src/Generated/AssetData.lua with base64 PNG payloads.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const iconDir = path.join(here, "node_modules", "lucide-static", "icons");
const outFile = path.join(root, "src", "Generated", "AssetData.lua");

const CELL = 60;
const STROKE = 2.15;

// Library icon name -> lucide file name (first existing candidate wins)
const ICONS = {
  check: ["check"], x: ["x"], plus: ["plus"], minus: ["minus"],
  "chevron-down": ["chevron-down"], "chevron-up": ["chevron-up"],
  "chevron-left": ["chevron-left"], "chevron-right": ["chevron-right"],
  "chevrons-up-down": ["chevrons-up-down"], search: ["search"], copy: ["copy"],
  clipboard: ["clipboard-paste", "clipboard"], lock: ["lock"], unlock: ["lock-open", "unlock"],
  eye: ["eye"], "eye-off": ["eye-off"], info: ["info"], "circle-check": ["circle-check", "check-circle"],
  "circle-x": ["circle-x", "x-circle"], "triangle-alert": ["triangle-alert", "alert-triangle"],
  "circle-alert": ["circle-alert", "alert-circle"], "circle-help": ["circle-help", "help-circle"],
  bell: ["bell"], settings: ["settings"], sliders: ["sliders-horizontal"], palette: ["palette"],
  keyboard: ["keyboard"], pointer: ["mouse-pointer-click", "mouse-pointer"], save: ["save"],
  folder: ["folder"], "folder-open": ["folder-open"], file: ["file-text"], download: ["download"],
  upload: ["upload"], trash: ["trash-2"], refresh: ["refresh-cw"], undo: ["rotate-ccw"],
  "log-out": ["log-out"], power: ["power"], maximize: ["maximize-2"], minimize: ["minimize-2"],
  grip: ["grip-vertical"], external: ["external-link"], filter: ["filter", "funnel"], list: ["list"],
  grid: ["layout-grid"], dashboard: ["layout-dashboard"], home: ["house", "home"], user: ["user"],
  users: ["users"], star: ["star"], heart: ["heart"], zap: ["zap"], shield: ["shield"],
  "shield-check": ["shield-check"], swords: ["swords"], sword: ["sword"], target: ["target"],
  crosshair: ["crosshair"], flame: ["flame"], crown: ["crown"], trophy: ["trophy"], gift: ["gift"],
  coins: ["coins"], wallet: ["wallet"], gem: ["gem"], rocket: ["rocket"], sparkles: ["sparkles"],
  wand: ["wand-sparkles", "wand"], gamepad: ["gamepad-2"], code: ["code"], terminal: ["terminal"],
  cpu: ["cpu"], wifi: ["wifi"], globe: ["globe"], map: ["map"], "map-pin": ["map-pin"],
  compass: ["compass"], navigation: ["navigation"], car: ["car"], plane: ["plane"],
  activity: ["activity"], "chart-line": ["chart-line", "line-chart"], "chart-bar": ["chart-column", "bar-chart-3"],
  "chart-pie": ["chart-pie", "pie-chart"], layers: ["layers"], box: ["box"], package: ["package"],
  wrench: ["wrench"], hammer: ["hammer"], bug: ["bug"], moon: ["moon"], sun: ["sun"],
  music: ["music"], image: ["image"], camera: ["camera"], video: ["video"],
  message: ["message-circle"], send: ["send"], bookmark: ["bookmark"], calendar: ["calendar"],
  clock: ["clock"], timer: ["timer"], hourglass: ["hourglass"], link: ["link"], hash: ["hash"],
  at: ["at-sign"], fingerprint: ["fingerprint"], key: ["key-round", "key"], ghost: ["ghost"],
  skull: ["skull"], footprints: ["footprints"], move: ["move"], monitor: ["monitor"],
  smartphone: ["smartphone"], server: ["server"], database: ["database"], cloud: ["cloud"],
  droplet: ["droplet"], wind: ["wind"], snowflake: ["snowflake"], leaf: ["leaf"],
  pickaxe: ["pickaxe"], cart: ["shopping-cart"], store: ["store"], "badge-check": ["badge-check"],
  award: ["award"], flag: ["flag"], battery: ["battery-medium", "battery"], gauge: ["gauge"],
  radar: ["radar"], scroll: ["scroll-text", "scroll"], book: ["book-open"], brain: ["brain"],
  bot: ["bot"], circle: ["circle"], square: ["square"], toggle: ["toggle-right"],
  "list-checks": ["list-checks"], "trending-up": ["trending-up"], "trending-down": ["trending-down"],
  "arrow-up-right": ["arrow-up-right"], "arrow-down-right": ["arrow-down-right"],
  repeat: ["repeat"], shuffle: ["shuffle"], play: ["play"], pause: ["pause"],
  volume: ["volume-2"], mic: ["mic"], headphones: ["headphones"], type: ["type"],
  pencil: ["pencil"], sparkle: ["sparkle"], command: ["command"], "panel-left": ["panel-left"],
  "ellipsis": ["ellipsis", "more-horizontal"], "loader": ["loader-circle", "loader-2"],
  inbox: ["inbox"], tag: ["tag"], "rotate-cw": ["rotate-cw"], "arrow-right": ["arrow-right"],
  "arrow-left": ["arrow-left"], "arrow-up": ["arrow-up"], "arrow-down": ["arrow-down"],
};

function readIcon(candidates) {
  for (const c of candidates) {
    const p = path.join(iconDir, `${c}.svg`);
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf8");
  }
  return null;
}

function prepSvg(svg) {
  return svg
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/currentColor/g, "#ffffff")
    .replace(/width="24"/, `width="${CELL}"`)
    .replace(/height="24"/, `height="${CELL}"`)
    .replace(/stroke-width="2"/, `stroke-width="${STROKE}"`);
}

async function buildAtlas() {
  const names = Object.keys(ICONS);
  const found = [];
  const missing = [];
  for (const name of names) {
    const svg = readIcon(ICONS[name]);
    if (svg) found.push({ name, svg: prepSvg(svg) });
    else missing.push(name);
  }
  if (missing.length) console.warn("Missing icons:", missing.join(", "));
  const cols = 16;
  const GAP = 4; // transparent gutter prevents bilinear bleeding between cells
  const STRIDE = CELL + GAP;
  const rows = Math.ceil(found.length / cols);
  const width = cols * STRIDE;
  const height = rows * STRIDE;
  const composites = [];
  const map = {};
  for (let i = 0; i < found.length; i++) {
    const x = (i % cols) * STRIDE + GAP / 2;
    const y = Math.floor(i / cols) * STRIDE + GAP / 2;
    const png = await sharp(Buffer.from(found[i].svg), { density: 288 })
      .resize(CELL, CELL, { kernel: sharp.kernel.lanczos3 })
      .png({ compressionLevel: 9, palette: false })
      .toBuffer();
    composites.push({ input: png, left: x, top: y });
    map[found[i].name] = [x, y];
  }
  const atlas = await sharp({
    create: { width, height, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 0 } },
  })
    .composite(composites)
    .png({ compressionLevel: 9, palette: false })
    .toBuffer();
  return { atlas, width, height, map, count: found.length };
}

function rawPng(width, height, fn) {
  const buf = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = fn(x, y);
      const i = (y * width + x) * 4;
      buf[i] = r; buf[i + 1] = g; buf[i + 2] = b; buf[i + 3] = a;
    }
  }
  return sharp(buf, { raw: { width, height, channels: 4 } });
}

async function buildGlow() {
  const S = 256;
  const c = (S - 1) / 2;
  return rawPng(S, S, (x, y) => {
    const r = Math.hypot(x - c, y - c) / c;
    const t = Math.max(0, 1 - r);
    const a = Math.round(255 * Math.pow(t, 2.1));
    return [255, 255, 255, a];
  }).png({ compressionLevel: 9, palette: true, colours: 256 }).toBuffer();
}

async function buildShadow() {
  // 160x160 source, rounded rect inset 40px, blurred. SliceCenter = (64,64,96,96)
  const S = 160;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}"><rect x="40" y="40" width="80" height="80" rx="18" ry="18" fill="#000"/></svg>`;
  return sharp(Buffer.from(svg)).blur(13).png({ compressionLevel: 9, palette: true, colours: 256 }).toBuffer();
}

async function buildNoise() {
  const S = 128;
  let seed = 1337;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };
  return rawPng(S, S, () => {
    const v = rand();
    return [255, 255, 255, Math.round(v * v * 90)];
  }).png({ compressionLevel: 9, palette: true, colours: 32 }).toBuffer();
}

function luaString(s) {
  return `"${s}"`;
}

async function buildGlass() {
  const s = 256;
  return rawPng(s, s, (x, y) => {
    const nx = x / (s - 1);
    const ny = y / (s - 1);
    // Diagonal top-left frosted specular sheen + soft lower-right secondary bounce
    const diag = nx * 0.58 + ny * 0.42;
    const primaryBand = Math.exp(-Math.pow((diag - 0.16) * 3.4, 2));
    const secondaryBand = Math.exp(-Math.pow((diag - 0.78) * 4.5, 2)) * 0.35;
    // Top & left edge catch
    const topEdge = Math.exp(-ny * 18) * 0.65;
    const leftEdge = Math.exp(-nx * 14) * 0.3;
    const luminance = Math.min(1, primaryBand * 0.48 + secondaryBand * 0.28 + topEdge * 0.38 + leftEdge * 0.28);
    const alpha = Math.min(255, Math.round(luminance * 145));
    // Cool frosted obsidian tint
    const r = Math.round(230 + 25 * topEdge);
    const g = Math.round(232 + 23 * topEdge);
    const b = 255;
    return [r, g, b, alpha];
  }).png({ compressionLevel: 9 }).toBuffer();
}

async function buildBanner() {
  const w = 640;
  const h = 200;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#08080E"/>
      <stop offset="55%" stop-color="#110E1F"/>
      <stop offset="100%" stop-color="#0B0C16"/>
    </linearGradient>
    <radialGradient id="auroraPurple" cx="0.78" cy="0.22" r="0.58">
      <stop offset="0%" stop-color="#A855F7" stop-opacity="0.52"/>
      <stop offset="45%" stop-color="#7C3AED" stop-opacity="0.24"/>
      <stop offset="100%" stop-color="#7C3AED" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="auroraCyan" cx="0.18" cy="0.78" r="0.52">
      <stop offset="0%" stop-color="#22D3EE" stop-opacity="0.22"/>
      <stop offset="50%" stop-color="#4F46E5" stop-opacity="0.14"/>
      <stop offset="100%" stop-color="#4F46E5" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="cardGlass" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1E1A30" stop-opacity="0.88"/>
      <stop offset="100%" stop-color="#0E0E18" stop-opacity="0.72"/>
    </linearGradient>
    <linearGradient id="cardStroke" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#E9D5FF" stop-opacity="0.45"/>
      <stop offset="45%" stop-color="#A855F7" stop-opacity="0.22"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.06"/>
    </linearGradient>
    <linearGradient id="splineStroke" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#38BDF8"/>
      <stop offset="52%" stop-color="#C084FC"/>
      <stop offset="100%" stop-color="#F472B6"/>
    </linearGradient>
    <linearGradient id="splineFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#A855F7" stop-opacity="0.34"/>
      <stop offset="100%" stop-color="#A855F7" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="accentPill" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#9333EA"/>
      <stop offset="100%" stop-color="#38BDF8"/>
    </linearGradient>
    <linearGradient id="bottomVignette" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#08080E" stop-opacity="0"/>
      <stop offset="100%" stop-color="#07070C" stop-opacity="0.58"/>
    </linearGradient>
  </defs>

  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <rect width="${w}" height="${h}" fill="url(#auroraPurple)"/>
  <rect width="${w}" height="${h}" fill="url(#auroraCyan)"/>

  <!-- Subtle architectural grid fade -->
  <g stroke="#8B5CF6" stroke-opacity="0.11" stroke-width="1">
    <line x1="80" y1="0" x2="80" y2="200"/>
    <line x1="160" y1="0" x2="160" y2="200"/>
    <line x1="240" y1="0" x2="240" y2="200"/>
    <line x1="320" y1="0" x2="320" y2="200"/>
    <line x1="400" y1="0" x2="400" y2="200"/>
    <line x1="480" y1="0" x2="480" y2="200"/>
    <line x1="560" y1="0" x2="560" y2="200"/>
    <line x1="0" y1="40" x2="640" y2="40"/>
    <line x1="0" y1="80" x2="640" y2="80"/>
    <line x1="0" y1="120" x2="640" y2="120"/>
    <line x1="0" y1="160" x2="640" y2="160"/>
  </g>

  <!-- Flowing luminous ribbon behind UI cards -->
  <path d="M -20 132 C 110 88, 220 156, 360 94 C 480 42, 570 96, 660 54" fill="none" stroke="url(#splineStroke)" stroke-opacity="0.22" stroke-width="2.5"/>

  <!-- Back glass control card (center-right) -->
  <g transform="translate(274, 28) rotate(-2)">
    <rect x="0" y="0" width="176" height="84" rx="12" fill="url(#cardGlass)" stroke="url(#cardStroke)" stroke-width="1"/>
    <rect x="14" y="14" width="66" height="8" rx="4" fill="#E9D5FF" fill-opacity="0.22"/>
    <rect x="14" y="29" width="44" height="5" rx="2.5" fill="#94A3B8" fill-opacity="0.25"/>
    <!-- Toggle pill -->
    <rect x="128" y="13" width="34" height="18" rx="9" fill="#9333EA"/>
    <circle cx="153" cy="22" r="6.5" fill="#FFFFFF"/>
    <!-- Progress track -->
    <rect x="14" y="54" width="148" height="6" rx="3" fill="#FFFFFF" fill-opacity="0.08"/>
    <rect x="14" y="54" width="106" height="6" rx="3" fill="url(#accentPill)"/>
    <circle cx="120" cy="57" r="5" fill="#FFFFFF"/>
  </g>

  <!-- Main foreground telemetry glass card (right) -->
  <g transform="translate(382, 20)">
    <rect x="0" y="0" width="234" height="134" rx="14" fill="url(#cardGlass)" stroke="url(#cardStroke)" stroke-width="1.2"/>
    <!-- Card header chrome -->
    <circle cx="16" cy="16" r="3" fill="#F472B6" fill-opacity="0.8"/>
    <circle cx="27" cy="16" r="3" fill="#FBBF24" fill-opacity="0.75"/>
    <circle cx="38" cy="16" r="3" fill="#34D399" fill-opacity="0.8"/>
    <rect x="56" y="12.5" width="76" height="7" rx="3.5" fill="#E2E8F0" fill-opacity="0.20"/>
    <rect x="176" y="10" width="44" height="12" rx="6" fill="#A855F7" fill-opacity="0.28" stroke="#C084FC" stroke-opacity="0.45" stroke-width="0.8"/>

    <!-- Subtle chart horizontal guide lines -->
    <line x1="16" y1="48" x2="218" y2="48" stroke="#FFFFFF" stroke-opacity="0.06" stroke-width="1"/>
    <line x1="16" y1="76" x2="218" y2="76" stroke="#FFFFFF" stroke-opacity="0.06" stroke-width="1"/>
    <line x1="16" y1="104" x2="218" y2="104" stroke="#FFFFFF" stroke-opacity="0.06" stroke-width="1"/>

    <!-- Telemetry spline fill + stroke -->
    <path d="M 16 106 C 48 102, 62 66, 94 74 C 122 80, 144 38, 174 44 C 194 48, 206 34, 218 32 L 218 118 L 16 118 Z" fill="url(#splineFill)"/>
    <path d="M 16 106 C 48 102, 62 66, 94 74 C 122 80, 144 38, 174 44 C 194 48, 206 34, 218 32" fill="none" stroke="url(#splineStroke)" stroke-width="2.4" stroke-linecap="round"/>

    <!-- Active telemetry nodes -->
    <circle cx="94" cy="74" r="3.2" fill="#C084FC"/>
    <circle cx="174" cy="44" r="7" fill="#A855F7" fill-opacity="0.26"/>
    <circle cx="174" cy="44" r="3.6" fill="#FFFFFF" stroke="#C084FC" stroke-width="1.4"/>
    <circle cx="218" cy="32" r="3.4" fill="#38BDF8"/>
  </g>

  <!-- Subtle bottom legibility vignette -->
  <rect width="${w}" height="${h}" fill="url(#bottomVignette)"/>
</svg>`;
  return sharp(Buffer.from(svg)).png({ compressionLevel: 9, palette: true, colours: 256, dither: 1.0 }).toBuffer();
}

async function main() {
  const { atlas, width, height, map, count } = await buildAtlas();
  const glow = await buildGlow();
  const shadow = await buildShadow();
  const noise = await buildNoise();
  const glass = await buildGlass();
  const banner = await buildBanner();

  const entries = Object.entries(map)
    .map(([k, [x, y]]) => `\t\t[${luaString(k)}] = { ${x}, ${y} },`)
    .join("\n");

  const lua = `-- AUTO-GENERATED by tools/assets/generate.mjs. Do not edit by hand.
-- Icons: Lucide (ISC License) https://lucide.dev
return {
\tVersion = "5",
\tAtlas = {
\t\tWidth = ${width},
\t\tHeight = ${height},
\t\tCell = ${CELL},
\t\tData = [[${atlas.toString("base64")}]],
\t},
\tIcons = {
${entries}
\t},
\tGlow = [[${glow.toString("base64")}]],
\tShadow = [[${shadow.toString("base64")}]],
\tNoise = [[${noise.toString("base64")}]],
\tGlass = [[${glass.toString("base64")}]],
\tBanner = [[${banner.toString("base64")}]],
}
`;
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, lua);
  // Preview copies for inspection
  const preview = path.join(here, "preview");
  fs.mkdirSync(preview, { recursive: true });
  fs.writeFileSync(path.join(preview, "atlas.png"), atlas);
  fs.writeFileSync(path.join(preview, "glow.png"), glow);
  fs.writeFileSync(path.join(preview, "shadow.png"), shadow);
  fs.writeFileSync(path.join(preview, "noise.png"), noise);
  fs.writeFileSync(path.join(preview, "glass.png"), glass);
  fs.writeFileSync(path.join(preview, "banner.png"), banner);
  console.log(`icons=${count} atlas=${width}x${height} atlasBytes=${atlas.length} glow=${glow.length} shadow=${shadow.length} noise=${noise.length} glass=${glass.length} banner=${banner.length} lua=${lua.length}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
