import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { defineComponent, ref } from 'vue';
import axios from 'axios';
import { emitter } from 'shared/helpers/mitt';
import { withFullI18n } from 'test-i18n';
import { useCopilotReply } from '../useCopilotReply';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';

vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useConfig');
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings: vi.fn() }),
}));

describe('useCaptain task API errors', () => {
  let wrapper;
  let originalAdapter;
  let toastHandler;
  const toasts = [];

  beforeAll(() => withFullI18n('en'));

  beforeEach(() => {
    vi.clearAllMocks();
    toasts.length = 0;
    toastHandler = payload => toasts.push(payload);
    emitter.on('newToastMessage', toastHandler);
    originalAdapter = axios.defaults.adapter;
    window.axios = axios;
    window.history.pushState({}, '', '/app/accounts/1/inbox/1');
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: () => true,
      currentAccount: ref({
        id: 1,
        limits: { plan: { period_end: '2026-11-01T00:00:00Z' } },
      }),
    });
    useConfig.mockReturnValue({ isEnterprise: false });
  });

  afterEach(() => {
    emitter.off('newToastMessage', toastHandler);
    axios.defaults.adapter = originalAdapter;
    wrapper?.unmount();
    wrapper = null;
  });

  const mountComposable = () => {
    const store = createStore({
      getters: {
        'accounts/getUIFlags': () => ({ isFetchingLimits: false }),
        getSelectedChat: () => ({ id: 12 }),
        'draftMessages/getReplyEditorMode': () => 'reply',
        'draftMessages/get': () => () => 'Draft message',
      },
    });
    let copilotReply;
    wrapper = mount(
      defineComponent({
        setup() {
          copilotReply = useCopilotReply();
          return () => null;
        },
      }),
      { global: { plugins: [store] } }
    );
    return copilotReply;
  };

  it.each([
    [403, 'not included in your plan'],
    [
      429,
      new Date('2026-11-01T00:00:00Z').toLocaleDateString('en-US', {
        timeZone: 'UTC',
      }),
    ],
    [502, 'provider could not complete this request'],
  ])(
    'shows the translated message for HTTP %i via the real axios client',
    async (status, expectedMessage) => {
      axios.defaults.adapter = config => {
        const error = new Error('Request failed');
        error.config = config;
        error.response = {
          config,
          status,
          headers: {},
          data: { error: 'server detail', error_code: status },
        };
        return Promise.reject(error);
      };

      const copilotReply = mountComposable();
      await copilotReply.execute('reply_suggestion', '');

      expect(copilotReply.errorMessage.value).toContain(expectedMessage);
      expect(toasts).toHaveLength(1);
      expect(toasts[0].message).toContain(expectedMessage);
      expect(toasts[0].message).not.toContain('server detail');
    }
  );
});
