import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import MessageList from './MessageList.vue';
import MessageApi from 'dashboard/api/inbox/message.js';

const account = { id: 1, locale: 'en', settings: { auto_translate: true } };
let featureEnabled = true;
let conversationId = 42;

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: key =>
    computed(() => {
      if (key === 'getSelectedChat') return { id: conversationId };
      return () => featureEnabled;
    }),
}));

vi.mock('./Message.vue', () => ({ default: { template: '<div />' } }));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: computed(() => account) }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: computed(() => ({ locale: 'en' })) }),
}));

vi.mock('dashboard/composables/useDarkMode', () => ({
  useDarkMode: () => ({ isDark: computed(() => false) }),
}));

vi.mock('dashboard/composables/useChatCanvas', () => ({
  useChatCanvas: () => ({ currentCanvasId: computed(() => null) }),
}));

vi.mock('dashboard/helper/chatSkin', () => ({ chatPanelStyle: () => ({}) }));

vi.mock('dashboard/composables/useTransformKeys', () => ({
  useCamelCase: value => value,
}));

vi.mock('dashboard/api/inbox/message.js', () => ({
  default: { autoTranslate: vi.fn(() => Promise.resolve()) },
}));

const incomingMessage = id => ({
  id,
  content: `Message ${id}`,
  message_type: 0,
  private: false,
  content_attributes: {},
});

const render = messages =>
  mount(MessageList, {
    props: { currentUserId: 7, messages },
    global: {
      stubs: {
        Message: true,
      },
      mocks: {
        $t: key => key,
      },
    },
  });

describe('MessageList automatic translation', () => {
  beforeEach(() => {
    featureEnabled = true;
    conversationId = 42;
    MessageApi.autoTranslate.mockClear();
  });

  it('does not request translations when the account feature is off', async () => {
    featureEnabled = false;
    render([incomingMessage(1)]);
    await nextTick();

    expect(MessageApi.autoTranslate).not.toHaveBeenCalled();
  });

  it('requests at most 20 untranslated incoming messages once per view', async () => {
    const messages = Array.from({ length: 25 }, (_, index) =>
      incomingMessage(index + 1)
    );
    const wrapper = render(messages);
    await nextTick();

    expect(MessageApi.autoTranslate).toHaveBeenCalledTimes(1);
    expect(MessageApi.autoTranslate).toHaveBeenCalledWith(
      42,
      Array.from({ length: 20 }, (_, index) => index + 6)
    );

    await wrapper.setProps({ messages: [...messages] });
    expect(MessageApi.autoTranslate).toHaveBeenCalledTimes(1);
  });
});
