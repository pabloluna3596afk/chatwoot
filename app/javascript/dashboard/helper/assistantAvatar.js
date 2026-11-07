import { ref } from 'vue';

export const DEFAULT_ASSISTANT_AVATAR_LIGHT = 'captain/avatar-light.svg';
export const DEFAULT_ASSISTANT_AVATAR_DARK = 'captain/avatar-dark.svg';

export const COPILOT_AVATAR_LIGHT = 'copilot/copilot-light.svg';
export const COPILOT_AVATAR_DARK = 'copilot/copilot-dark.svg';

const AVATAR_PAIRS = [
  [DEFAULT_ASSISTANT_AVATAR_LIGHT, DEFAULT_ASSISTANT_AVATAR_DARK],
  [COPILOT_AVATAR_LIGHT, COPILOT_AVATAR_DARK],
];
const findPair = src => AVATAR_PAIRS.find(([light]) => src?.endsWith(light));

const isDark = ref(false);
let observing = false;

const readDarkMode = () => document.body.classList.contains('dark');

// One shared observer, started the first time a default assistant avatar is resolved,
// so lists of avatars don't each watch the body class.
const observeTheme = () => {
  if (observing || typeof document === 'undefined') return;
  observing = true;
  isDark.value = readDarkMode();
  new MutationObserver(() => {
    isDark.value = readDarkMode();
  }).observe(document.body, { attributes: true, attributeFilter: ['class'] });
};

export const swapDefaultAssistantAvatar = (src, dark) => {
  const pair = findPair(src);
  if (!dark || !pair) return src;
  return src.replace(pair[0], pair[1]);
};

// Reads a ref, so calling it inside a computed or template re-renders on a theme change.
export const resolveAssistantAvatar = src => {
  if (!findPair(src)) return src;
  observeTheme();
  return swapDefaultAssistantAvatar(src, isDark.value);
};
