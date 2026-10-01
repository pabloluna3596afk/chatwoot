import {
  DEFAULT_ASSISTANT_AVATAR_DARK,
  DEFAULT_ASSISTANT_AVATAR_LIGHT,
  resolveAssistantAvatar,
  swapDefaultAssistantAvatar,
} from '../assistantAvatar';

const LIGHT_URL = `https://chat.example.com/assets/images/dashboard/${DEFAULT_ASSISTANT_AVATAR_LIGHT}`;
const DARK_URL = `https://chat.example.com/assets/images/dashboard/${DEFAULT_ASSISTANT_AVATAR_DARK}`;
const waitForObserver = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

describe('assistantAvatar', () => {
  describe('swapDefaultAssistantAvatar', () => {
    it('swaps the default light avatar for the dark one in dark mode', () => {
      expect(swapDefaultAssistantAvatar(LIGHT_URL, true)).toBe(DARK_URL);
    });

    it('keeps the light avatar in light mode', () => {
      expect(swapDefaultAssistantAvatar(LIGHT_URL, false)).toBe(LIGHT_URL);
    });

    it('never touches an uploaded photo or an empty src', () => {
      const photo = 'https://chat.example.com/rails/active_storage/photo.png';

      expect(swapDefaultAssistantAvatar(photo, true)).toBe(photo);
      expect(swapDefaultAssistantAvatar('', true)).toBe('');
      expect(swapDefaultAssistantAvatar(undefined, true)).toBeUndefined();
    });
  });

  describe('resolveAssistantAvatar', () => {
    afterEach(() => document.body.classList.remove('dark'));

    it('returns other sources untouched', () => {
      expect(resolveAssistantAvatar('https://x.test/a.png')).toBe(
        'https://x.test/a.png'
      );
      expect(resolveAssistantAvatar('')).toBe('');
    });

    it('follows the theme of the page', async () => {
      expect(resolveAssistantAvatar(LIGHT_URL)).toBe(LIGHT_URL);

      document.body.classList.add('dark');
      await waitForObserver();
      expect(resolveAssistantAvatar(LIGHT_URL)).toBe(DARK_URL);

      document.body.classList.remove('dark');
      await waitForObserver();
      expect(resolveAssistantAvatar(LIGHT_URL)).toBe(LIGHT_URL);
    });
  });
});
