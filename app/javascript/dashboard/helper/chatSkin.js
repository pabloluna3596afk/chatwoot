import doodleTileLight from 'dashboard/assets/images/chat/doodle-tile-light.svg';
import doodleTileDark from 'dashboard/assets/images/chat/doodle-tile-dark.svg';

export const CHAT_SKIN = {
  light: {
    bg: '#efeae2',
    tile: doodleTileLight,
  },
  dark: {
    bg: '#0b141a',
    tile: doodleTileDark,
  },
  tileSize: '280px',
  bubble: {
    incoming: 'bg-white shadow-sm dark:bg-[#1f2c34] text-n-slate-12',
    outgoing: 'bg-[#dcf8c6] dark:bg-[#005c4b] text-n-slate-12',
  },
};

export function chatPanelStyle(isDark) {
  const theme = isDark ? CHAT_SKIN.dark : CHAT_SKIN.light;

  return {
    backgroundColor: theme.bg,
    backgroundImage: `url(${theme.tile})`,
    backgroundRepeat: 'repeat',
    backgroundSize: CHAT_SKIN.tileSize,
  };
}
