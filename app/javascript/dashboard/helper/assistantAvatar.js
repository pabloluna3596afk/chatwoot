import { ref } from 'vue';

export const DEFAULT_ASSISTANT_AVATAR_LIGHT = 'captain/avatar-light.svg';
export const DEFAULT_ASSISTANT_AVATAR_DARK = 'captain/avatar-dark.svg';

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
  if (!dark || !src?.endsWith(DEFAULT_ASSISTANT_AVATAR_LIGHT)) return src;
  return src.replace(
    DEFAULT_ASSISTANT_AVATAR_LIGHT,
    DEFAULT_ASSISTANT_AVATAR_DARK
  );
};

// Reads a ref, so calling it inside a computed or template re-renders on a theme change.
export const resolveAssistantAvatar = src => {
  if (!src?.endsWith(DEFAULT_ASSISTANT_AVATAR_LIGHT)) return src;
  observeTheme();
  return swapDefaultAssistantAvatar(src, isDark.value);
};
