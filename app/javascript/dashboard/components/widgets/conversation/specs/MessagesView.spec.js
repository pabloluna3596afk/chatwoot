import { shallowMount, flushPromises } from '@vue/test-utils';
import { nextTick, ref, reactive } from 'vue';
import { createStore } from 'vuex';
import MessagesView from '../MessagesView.vue';

vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: false,
    isLabelSuggestionFeatureEnabled: false,
  }),
}));
const isReadingHistory = ref(false);
const latestConversation = ref(null);
const leaveReadingMode = vi.fn();
const navigate = vi.fn();
vi.mock('dashboard/composables/useContactConversationNavigation', () => ({
  useContactConversationNavigation: () => ({
    isReadingHistory,
    latestConversation,
    leaveReadingMode,
    buildConversationPath: id => `/conversations/${id}`,
  }),
}));

describe('MessagesView list resizing', () => {
  let wrapper;
  let observers;
  let panel;
  let height;
  let scrollToBottom;
  let phoneMedia;
  let mediaListeners;

  beforeEach(async () => {
    observers = [];
    isReadingHistory.value = false;
    latestConversation.value = null;
    leaveReadingMode.mockImplementation(() => {
      isReadingHistory.value = false;
    });
    sessionStorage.clear();
    window.cw_keyboard_layout = 'QWERTY';
    mediaListeners = [];
    phoneMedia = {
      matches: false,
      media: '(max-width: 767px)',
      addEventListener: (_event, callback) => mediaListeners.push(callback),
      removeEventListener: vi.fn(),
    };
    vi.stubGlobal(
      'matchMedia',
      vi.fn(() => phoneMedia)
    );
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
        getSelectedChat: () =>
          reactive({
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
      global: {
        plugins: [store],
        mocks: { $route: { query: {} }, $router: { push: navigate } },
        stubs: {
          transition: false,
          ResizableEditorWrapper: { template: '<div><slot/></div>' },
          ReplyBox: {
            name: 'ReplyBox',
            emits: ['collapse'],
            data: () => ({
              message: '',
              hasAttachments: 0,
              replyType: 'REPLY',
              canSendPublicReply: true,
            }),
            methods: {
              setReplyMode(mode) {
                this.replyType = mode;
              },
            },
            template: '<div class="test-editor" />',
          },
        },
      },
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

  it('folds an empty history editor and offers the upstream latest action', async () => {
    isReadingHistory.value = true;
    latestConversation.value = { id: 7 };
    await nextTick();
    const bar = wrapper.getComponent({ name: 'CollapsedReplyBar' });
    expect(bar.props('replyLabel')).toBe(
      'CONVERSATION.CONTACT_HISTORY.REPLY_TO_OLDER'
    );
    expect(bar.props('hasLatest')).toBe(true);
    bar.vm.$emit('goToLatest');
    expect(navigate).toHaveBeenCalledWith('/conversations/7');
    expect(wrapper.vm.isReplyFolded).toBe(true);
  });

  it.each([{ message: 'Draft' }, { hasAttachments: 1 }])(
    'does not auto-fold with a draft %s',
    async draft => {
      Object.assign(wrapper.getComponent({ name: 'ReplyBox' }).vm, draft);
      isReadingHistory.value = true;
      await nextTick();
      expect(wrapper.vm.isReplyFolded).toBe(false);
      expect(
        wrapper.findComponent({ name: 'CollapsedReplyBar' }).exists()
      ).toBe(false);
    }
  );

  it.each(['L', 'P'])(
    'collapses explicitly and Alt+%s reveals the editor',
    async key => {
      await flushPromises();
      wrapper.getComponent({ name: 'ReplyBox' }).vm.$emit('collapse');
      await nextTick();
      expect(wrapper.vm.isReplyFolded).toBe(true);
      document.dispatchEvent(
        new KeyboardEvent('keydown', {
          key: key.toLowerCase(),
          code: `Key${key}`,
          altKey: true,
          bubbles: true,
        })
      );
      await flushPromises();
      expect(wrapper.vm.isReplyFolded).toBe(false);
      expect(leaveReadingMode).toHaveBeenCalled();
    }
  );

  it('reopens a manually hidden draft in the same mode without resetting its attachments', async () => {
    const editor = wrapper.getComponent({ name: 'ReplyBox' });
    editor.vm.message = 'Keep this draft';
    editor.vm.hasAttachments = 1;
    const switchMode = vi.spyOn(editor.vm, 'setReplyMode');
    editor.vm.$emit('collapse');
    await nextTick();
    wrapper
      .getComponent({ name: 'CollapsedReplyBar' })
      .vm.$emit('open', 'REPLY');
    await flushPromises();
    expect(editor.vm.message).toBe('Keep this draft');
    expect(editor.vm.hasAttachments).toBe(1);
    expect(switchMode).not.toHaveBeenCalled();
  });

  it('offers a smooth jump to the latest message only when scrolled away from the bottom', async () => {
    const scrollTo = vi.fn();
    panel.scrollTo = scrollTo;
    wrapper.vm.handleScroll({
      target: { scrollHeight: 2000, scrollTop: 500, clientHeight: 600 },
    });
    await nextTick();
    expect(wrapper.vm.showScrollToLatest).toBe(true);
    wrapper.vm.scrollToLatest();
    expect(scrollTo).toHaveBeenCalledWith({ top: 2000, behavior: 'smooth' });
    wrapper.vm.handleScroll({
      target: { scrollHeight: 2000, scrollTop: 1380, clientHeight: 600 },
    });
    await nextTick();
    expect(wrapper.vm.showScrollToLatest).toBe(false);
  });

  it('centers an opaque 40px latest arrow above the composer with focus and unread count', async () => {
    wrapper.vm.handleScroll({
      target: { scrollHeight: 2000, scrollTop: 500, clientHeight: 600 },
    });
    wrapper.vm.currentChat.unread_count = 3;
    wrapper.vm.$forceUpdate();
    await nextTick();
    const button = wrapper.get('[icon="i-lucide-arrow-down"]');
    expect(button.attributes('aria-label')).toBe(
      'CONVERSATION.SCROLL_TO_LATEST'
    );
    expect(button.classes()).toEqual(
      expect.arrayContaining([
        '!size-10',
        '!bg-n-solid-1',
        'hover:enabled:!bg-n-solid-1',
        'hover:shadow-lg',
        'focus-visible:ring-2',
      ])
    );
    expect([...button.element.parentElement.classList]).toEqual(
      expect.arrayContaining([
        'inset-x-0',
        'mx-auto',
        '-top-14',
        'max-md:-top-12',
      ])
    );
    expect(button.element.parentElement.textContent).toContain('3');
    panel.scrollTo = vi.fn();
    await button.trigger('click');
    expect(panel.scrollTo).toHaveBeenCalledWith({
      top: 2000,
      behavior: 'smooth',
    });
  });

  it('keeps the full-bleed top border', () => {
    expect(wrapper.get('.border-t').classes()).toContain('border-n-weak');
  });

  it('never folds on phone, including a persisted manual collapse or reading history', async () => {
    wrapper.vm.collapseReplyBox();
    isReadingHistory.value = true;
    latestConversation.value = { id: 7 };
    await nextTick();
    expect(wrapper.vm.isReplyFolded).toBe(true);
    phoneMedia.matches = true;
    mediaListeners.forEach(callback => callback(phoneMedia));
    await nextTick();
    expect(wrapper.vm.isReplyFolded).toBe(false);
    expect(wrapper.findComponent({ name: 'CollapsedReplyBar' }).exists()).toBe(
      false
    );
    expect(wrapper.get('.test-editor').isVisible()).toBe(true);
  });

  it('explicitly opens the older conversation without losing its mounted draft', async () => {
    isReadingHistory.value = true;
    await nextTick();
    const editor = wrapper.getComponent({ name: 'ReplyBox' });
    wrapper
      .getComponent({ name: 'CollapsedReplyBar' })
      .vm.$emit('open', 'REPLY');
    await flushPromises();
    expect(wrapper.vm.isReplyFolded).toBe(false);
    expect(leaveReadingMode).toHaveBeenCalled();
    expect(wrapper.getComponent({ name: 'ReplyBox' }).vm).toBe(editor.vm);
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

  it('does not jump to the end when the composer resizes during a quote lookup', () => {
    panel.scrollTop = 1400;
    wrapper.vm.messageJump.isJumping = true;
    height = 300;
    observers
      .find(observer => observer.observe.mock.calls[0]?.[0] === panel)
      .callback();
    expect(scrollToBottom).not.toHaveBeenCalled();
  });

  it('does not mark messages read for quote jumps, while preserving it for other sources', async () => {
    const jumpToMessage = vi
      .spyOn(wrapper.vm.messageJump, 'jumpToMessage')
      .mockResolvedValue('found');
    const makeMessagesRead = vi.spyOn(wrapper.vm, 'makeMessagesRead');

    await wrapper.vm.onScrollToMessage({ messageId: 4, source: 'reply' });
    expect(jumpToMessage).toHaveBeenCalledWith({
      messageId: 4,
      source: 'reply',
    });
    expect(makeMessagesRead).not.toHaveBeenCalled();

    await wrapper.vm.onScrollToMessage({ messageId: 4 });
    expect(makeMessagesRead).toHaveBeenCalledOnce();
  });

  it('disconnects its observer on unmount', () => {
    const observer = observers.find(
      item => item.observe.mock.calls[0]?.[0] === panel
    );
    wrapper.unmount();
    wrapper = undefined;
    expect(observer.disconnect).toHaveBeenCalledOnce();
  });

  it('releases programmatic scrolling on manual input and resumes history loading', () => {
    const fetchPrevious = vi.spyOn(wrapper.vm, 'fetchPreviousMessages');
    wrapper.vm.markProgrammaticScroll();
    wrapper.vm.handleScroll({ target: panel });
    expect(fetchPrevious).not.toHaveBeenCalled();
    panel.dispatchEvent(new Event('wheel'));
    expect(wrapper.vm.isProgrammaticScroll).toBe(false);
    wrapper.vm.handleScroll({ target: panel });
    expect(fetchPrevious).toHaveBeenCalledOnce();
  });

  it('removes the old scrollend listener when a newer scroll starts', () => {
    const remove = vi.spyOn(panel, 'removeEventListener');
    wrapper.vm.markProgrammaticScroll();
    const oldFinish = wrapper.vm.finishProgrammaticScroll;
    wrapper.vm.markProgrammaticScroll();
    expect(remove).toHaveBeenCalledWith('scrollend', oldFinish);
    panel.dispatchEvent(new Event('scrollend'));
    expect(wrapper.vm.isProgrammaticScroll).toBe(false);
  });

  it.each([true, false])(
    'new incoming messages follow only a pinned reader: %s',
    async pinned => {
      wrapper.vm.currentChat.messages.push({ id: 10 });
      await nextTick();
      panel.scrollTop = pinned ? 1400 : 400;
      scrollToBottom.mockClear();
      wrapper.vm.currentChat.messages.push({ id: 11 });
      await nextTick();
      await nextTick();
      expect(scrollToBottom).toHaveBeenCalledTimes(pinned ? 1 : 0);
    }
  );

  it('does not follow incoming messages during a quote lookup', async () => {
    wrapper.vm.currentChat.messages.push({ id: 10 });
    await nextTick();
    panel.scrollTop = 1400;
    wrapper.vm.messageJump.isJumping = true;
    scrollToBottom.mockClear();
    wrapper.vm.currentChat.messages.push({ id: 11 });
    await nextTick();
    await nextTick();
    expect(scrollToBottom).not.toHaveBeenCalled();
  });

  it('does not cancel the quote when the store announces an incoming message without a target', async () => {
    const jump = vi.spyOn(wrapper.vm.messageJump, 'jumpToMessage');
    wrapper.vm.hasUserScrolled = false;
    await wrapper.vm.onScrollToMessage();
    expect(jump).not.toHaveBeenCalled();
    expect(wrapper.vm.hasUserScrolled).toBe(false);
  });

  it('does not restore an older manual-pagination anchor after a quote takes over', async () => {
    wrapper.vm.currentChat.messages.push({ id: 100 });
    wrapper.vm.currentChat.dataFetched = true;
    wrapper.vm.isLoadingPrevious = false;
    Object.defineProperty(wrapper.vm, 'listLoadingStatus', {
      get: () => false,
    });
    let resolveHistory;
    const dispatch = vi.spyOn(wrapper.vm.$store, 'dispatch').mockImplementation(
      () =>
        new Promise(resolve => {
          resolveHistory = resolve;
        })
    );
    panel.scrollTop = 20;
    const pending = wrapper.vm.fetchPreviousMessages(20);
    const request = dispatch.mock.calls.at(-1)[1];
    vi.spyOn(wrapper.vm.messageJump, 'jumpToMessage').mockResolvedValue(
      'found'
    );
    await wrapper.vm.onScrollToMessage({ messageId: 100, source: 'reply' });
    panel.scrollTop = 800;
    expect(request.shouldApply()).toBe(false);
    resolveHistory();
    await pending;
    expect(panel.scrollTop).toBe(800);
  });
});
