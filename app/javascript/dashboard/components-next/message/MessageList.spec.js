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

  it('does not automatically request messages already pending or failed', async () => {
    render([
      {
        ...incomingMessage(1),
        content_attributes: { translation_status: 'pending' },
      },
      {
        ...incomingMessage(2),
        content_attributes: { translation_status: 'failed' },
      },
    ]);
    await nextTick();

    expect(MessageApi.autoTranslate).not.toHaveBeenCalled();
  });
});

describe('MessageList minute grouping', () => {
  beforeEach(() => {
    featureEnabled = false;
  });

  it.each([
    [1795125601, 1795125659, true],
    [1795125659, 1795125660, false],
    [1795125659, 1795129201, false],
  ])('groups timestamps %s and %s: %s', (first, second, grouped) => {
    const wrapper = render([
      { id: 1, senderId: 9, messageType: 1, createdAt: first },
      { id: 2, senderId: 9, messageType: 1, createdAt: second },
    ]);
    const messages = wrapper.findAllComponents({ name: 'Message' });
    expect(messages[0].attributes('group-with-next')).toBe(String(grouped));
    expect(messages[1].attributes('group-with-next')).toBe('false');
  });

  it('does not group a private note with a public reply', () => {
    const wrapper = render([
      {
        id: 1,
        senderId: 9,
        messageType: 1,
        createdAt: 1795125601,
        private: true,
      },
      {
        id: 2,
        senderId: 9,
        messageType: 1,
        createdAt: 1795125602,
        private: false,
      },
    ]);
    expect(
      wrapper
        .findAllComponents({ name: 'Message' })[0]
        .attributes('group-with-next')
    ).toBe('false');
  });
});
