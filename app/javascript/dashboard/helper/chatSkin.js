import comunicacionLight from 'dashboard/assets/images/chat/tiles/comunicacion-light.svg';
import comunicacionDark from 'dashboard/assets/images/chat/tiles/comunicacion-dark.svg';
import corazonesLight from 'dashboard/assets/images/chat/tiles/corazones-light.svg';
import corazonesDark from 'dashboard/assets/images/chat/tiles/corazones-dark.svg';
import estudioLight from 'dashboard/assets/images/chat/tiles/estudio-light.svg';
import estudioDark from 'dashboard/assets/images/chat/tiles/estudio-dark.svg';
import doodlesLight from 'dashboard/assets/images/chat/tiles/doodles-light.svg';
import doodlesDark from 'dashboard/assets/images/chat/tiles/doodles-dark.svg';

import previewComunicacion from 'dashboard/assets/images/chat/previews/comunicacion-light.svg';
import previewComunicacionDark from 'dashboard/assets/images/chat/previews/comunicacion-dark.svg';
import previewCorazones from 'dashboard/assets/images/chat/previews/corazones-light.svg';
import previewCorazonesDark from 'dashboard/assets/images/chat/previews/corazones-dark.svg';
import previewEstudio from 'dashboard/assets/images/chat/previews/estudio-light.svg';
import previewEstudioDark from 'dashboard/assets/images/chat/previews/estudio-dark.svg';
import previewDoodles from 'dashboard/assets/images/chat/previews/doodles-light.svg';
import previewDoodlesDark from 'dashboard/assets/images/chat/previews/doodles-dark.svg';
import previewPlain from 'dashboard/assets/images/chat/previews/plain-light.svg';
import previewPlainDark from 'dashboard/assets/images/chat/previews/plain-dark.svg';

export const DEFAULT_CHAT_CANVAS = 'comunicacion';

export const CHAT_CANVAS_IDS = [
  'comunicacion',
  'corazones',
  'estudio',
  'doodles',
  'plain',
];

/** Map previous ui_settings.chat_canvas values → new ids */
const LEGACY_CHAT_CANVAS = {
  classic: 'comunicacion',
  shapes: 'corazones',
  arrows: 'estudio',
};

const WA_BG = {
  light: '#EAE3D8',
  dark: '#0B141A',
};

const TILE_SIZE = '340px';

export const CHAT_CANVAS_THEMES = {
  comunicacion: {
    id: 'comunicacion',
    bg: WA_BG,
    tiles: { light: comunicacionLight, dark: comunicacionDark },
    preview: previewComunicacion,
    previewDark: previewComunicacionDark,
    tileSize: TILE_SIZE,
  },
  corazones: {
    id: 'corazones',
    bg: WA_BG,
    tiles: { light: corazonesLight, dark: corazonesDark },
    preview: previewCorazones,
    previewDark: previewCorazonesDark,
    tileSize: TILE_SIZE,
  },
  estudio: {
    id: 'estudio',
    bg: WA_BG,
    tiles: { light: estudioLight, dark: estudioDark },
    preview: previewEstudio,
    previewDark: previewEstudioDark,
    tileSize: TILE_SIZE,
  },
  doodles: {
    id: 'doodles',
    bg: WA_BG,
    tiles: { light: doodlesLight, dark: doodlesDark },
    preview: previewDoodles,
    previewDark: previewDoodlesDark,
    tileSize: TILE_SIZE,
  },
  plain: {
    id: 'plain',
    bg: WA_BG,
    tiles: null,
    preview: previewPlain,
    previewDark: previewPlainDark,
    tileSize: TILE_SIZE,
  },
};

/** Bubble colors shared across all canvases (WhatsApp-style). */
export const CHAT_SKIN = {
  bubble: {
    incoming: 'bg-white shadow-sm dark:bg-[#1f2c34] text-n-slate-12',
    outgoing: 'bg-[#dcf8c6] dark:bg-[#005c4b] text-n-slate-12',
  },
};

export function resolveChatCanvasId(canvasId) {
  const mapped = LEGACY_CHAT_CANVAS[canvasId] || canvasId;
  if (CHAT_CANVAS_IDS.includes(mapped)) return mapped;
  return DEFAULT_CHAT_CANVAS;
}

export function chatPanelStyle(isDark, canvasId = DEFAULT_CHAT_CANVAS) {
  const theme =
    CHAT_CANVAS_THEMES[resolveChatCanvasId(canvasId)] ||
    CHAT_CANVAS_THEMES[DEFAULT_CHAT_CANVAS];
  const bg = isDark ? theme.bg.dark : theme.bg.light;

  if (!theme.tiles) {
    return { backgroundColor: bg };
  }

  const tile = isDark ? theme.tiles.dark : theme.tiles.light;
  // Guard if a build still inlines SVGs as data-URLs (Vite # truncation).
  const safeTile =
    typeof tile === 'string' && tile.startsWith('data:')
      ? tile.replace(/#/g, '%23')
      : tile;

  return {
    backgroundColor: bg,
    backgroundImage: `url("${safeTile}")`,
    backgroundRepeat: 'repeat',
    backgroundSize: theme.tileSize,
  };
}
