import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const drafts = path.join(root, 'docs/chat-canvas-drafts');
const tilesOut = path.join(
  root,
  'app/javascript/dashboard/assets/images/chat/tiles'
);
const prevOut = path.join(
  root,
  'app/javascript/dashboard/assets/images/chat/previews'
);

const map = [
  ['01-comunicacion', 'comunicacion'],
  ['02-corazones', 'corazones'],
  ['03-estudio', 'estudio'],
  ['04-doodles', 'doodles'],
];

const bg = { light: '#EAE3D8', dark: '#0B141A' };

for (const [src, id] of map) {
  for (const mode of ['light', 'dark']) {
    const raw = fs.readFileSync(
      path.join(drafts, `${src}-${mode}.svg`),
      'utf8'
    );
    const m = raw.match(/<pattern[^>]*>([\s\S]*?)<\/pattern>/);
    if (!m) throw new Error(`no pattern in ${src}-${mode}`);
    const inner = m[1].trim();
    const tile = `<svg xmlns="http://www.w3.org/2000/svg" width="340" height="340" viewBox="0 0 340 340">
${inner}
</svg>
`;
    fs.writeFileSync(path.join(tilesOut, `${id}-${mode}.svg`), tile);
    const b64 = Buffer.from(tile).toString('base64');
    const preview = `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
  <rect width="100%" height="100%" fill="${bg[mode]}"/>
  <image href="data:image/svg+xml;base64,${b64}" width="120" height="120" preserveAspectRatio="xMidYMid slice"/>
</svg>
`;
    fs.writeFileSync(path.join(prevOut, `${id}-${mode}.svg`), preview);
    console.log('wrote', id, mode);
  }
}

fs.writeFileSync(
  path.join(prevOut, 'plain-light.svg'),
  `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120"><rect width="100%" height="100%" fill="#EAE3D8"/></svg>\n`
);
fs.writeFileSync(
  path.join(prevOut, 'plain-dark.svg'),
  `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120"><rect width="100%" height="100%" fill="#0B141A"/></svg>\n`
);
console.log('done');
