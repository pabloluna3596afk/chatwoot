import { nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import App from './App.vue';

vi.mock('vue-router', () => ({ useRouter: () => ({}) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: null }),
}));
vi.mock('dashboard/composables/useFontSize', () => ({
  useFontSize: () => ({ currentFontSize: '16px' }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: {} }),
}));
vi.mock('./helper/themeHelper', () => ({ setColorTheme: vi.fn() }));

describe('App visual viewport layout', () => {
  let wrapper;

  beforeEach(() => {
    vi.stubGlobal('chatwootConfig', { selectedLocale: null });
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => ({ matches: false }))
    );
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it.each(['iPhone', 'Android'])(
    'anchors the app to the visual viewport only on iOS (%s)',
    async userAgent => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(userAgent);
      const viewport = new EventTarget();
      viewport.height = 500;
      viewport.offsetTop = 180;
      vi.stubGlobal('visualViewport', viewport);
      wrapper = shallowMount(App, {
        global: {
          mocks: {
            $store: {
              getters: {
                'accounts/getAccount': vi.fn(),
                'accounts/isRTL': false,
                getCurrentUser: {},
                getAuthUIFlags: { isFetching: false },
              },
            },
          },
          stubs: { RouterView: true },
        },
      });
      await nextTick();

      const root = wrapper.get('#app');
      expect(root.classes().includes('fixed')).toBe(userAgent === 'iPhone');
      expect(root.classes().includes('top-[var(--app-offset-top)]')).toBe(
        userAgent === 'iPhone'
      );
      expect(root.classes()).toContain('!h-[var(--app-height,100dvh)]');
      if (userAgent === 'iPhone') {
        expect(
          document.documentElement.style.getPropertyValue('--app-offset-top')
        ).toBe('180px');
      }
    }
  );
});
