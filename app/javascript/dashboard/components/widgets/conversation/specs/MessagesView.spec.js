import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import MessagesView from '../MessagesView.vue';

vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: false,
    isLabelSuggestionFeatureEnabled: false,
  }),
}));
vi.mock('dashboard/composables/useContactConversationNavigation', () => ({
  useContactConversationNavigation: () => ({}),
}));

describe('MessagesView list resizing', () => {
  let wrapper;
  let observers;
  let panel;
  let height;
  let scrollToBottom;

  beforeEach(async () => {
    observers = [];
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(callback) {
          this.callback = callback;
          this.observe = vi.fn();
          this.unobserve = vi.fn();
          this.disconnect = vi.fn();
          observers.push(this);
        }
      }
    );
    const store = createStore({
      actions: { fetchAllAttachments: vi.fn(), fetchPreviousMessages: vi.fn() },
      getters: {
        getSelectedChat: () => ({
          id: 1,
          inbox_id: 1,
          status: 'open',
          can_reply: true,
          messages: [],
          labels: [],
        }),
        getCurrentUserID: () => 1,
        getAllMessagesLoaded: () => true,
        getCurrentAccountId: () => 1,
        'globalConfig/isMetaMessageSendingDisabled': () => false,
        'inboxes/getInbox': () => () => ({
          channel_type: 'Channel::WebWidget',
        }),
        'inboxes/getInstagramInboxByInstagramId': () => () => null,
        'conversationTypingStatus/getUserList': () => () => [],
      },
    });
    wrapper = shallowMount(MessagesView, {
      global: { plugins: [store], mocks: { $route: { query: {} } } },
    });
    await nextTick();
    panel = wrapper.get('.conversation-panel').element;
    height = 600;
    Object.defineProperties(panel, {
      clientHeight: { configurable: true, get: () => height },
      scrollHeight: { configurable: true, get: () => 2000 },
    });
    // Deliver the initial size, then position the reader before the keyboard opens.
    observers
      .find(observer => observer.observe.mock.calls[0]?.[0] === panel)
      .callback();
    scrollToBottom = vi.spyOn(wrapper.vm, 'scrollToBottom');
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it.each([0, 80])('pins when previously %s px from the end', distance => {
    panel.scrollTop = 1400 - distance;
    height = 300;
    observers
      .find(observer => observer.observe.mock.calls[0]?.[0] === panel)
      .callback();
    expect(scrollToBottom).toHaveBeenCalledOnce();
    expect(panel.scrollTop).toBeGreaterThan(1400);
  });

  it.each([81, 500])(
    'preserves reading position %s px from the end',
    distance => {
      panel.scrollTop = 1400 - distance;
      height = 300;
      observers
        .find(observer => observer.observe.mock.calls[0]?.[0] === panel)
        .callback();
      expect(scrollToBottom).not.toHaveBeenCalled();
      expect(panel.scrollTop).toBe(1400 - distance);
    }
  );

  it('ignores delivery without a height change', () => {
    panel.scrollTop = 1400;
    observers
      .find(observer => observer.observe.mock.calls[0]?.[0] === panel)
      .callback();
    expect(scrollToBottom).not.toHaveBeenCalled();
  });

  it('disconnects its observer on unmount', () => {
    const observer = observers.find(
      item => item.observe.mock.calls[0]?.[0] === panel
    );
    wrapper.unmount();
    wrapper = undefined;
    expect(observer.disconnect).toHaveBeenCalledOnce();
  });
});
