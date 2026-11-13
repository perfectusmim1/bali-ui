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

const CELL = 48;
const STROKE = 1.85;

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
    const png = await sharp(Buffer.from(found[i].svg), { density: 72 }).resize(CELL, CELL).png().toBuffer();
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
  }).png({ compressionLevel: 9 }).toBuffer();
}

async function buildShadow() {
  // 160x160 source, rounded rect inset 40px, blurred. SliceCenter = (64,64,96,96)
  const S = 160;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}"><rect x="40" y="40" width="80" height="80" rx="18" ry="18" fill="#000"/></svg>`;
  return sharp(Buffer.from(svg)).blur(13).png({ compressionLevel: 9 }).toBuffer();
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
  }).png({ compressionLevel: 9 }).toBuffer();
}

function luaString(s) {
  return `"${s}"`;
}

async function main() {
  const { atlas, width, height, map, count } = await buildAtlas();
  const glow = await buildGlow();
  const shadow = await buildShadow();
  const noise = await buildNoise();

  const entries = Object.entries(map)
    .map(([k, [x, y]]) => `\t\t[${luaString(k)}] = { ${x}, ${y} },`)
    .join("\n");

  const lua = `-- AUTO-GENERATED by tools/assets/generate.mjs. Do not edit by hand.
-- Icons: Lucide (ISC License) https://lucide.dev
return {
\tVersion = "3",
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
  console.log(`icons=${count} atlas=${width}x${height} atlasBytes=${atlas.length} glow=${glow.length} shadow=${shadow.length} noise=${noise.length} lua=${lua.length}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
