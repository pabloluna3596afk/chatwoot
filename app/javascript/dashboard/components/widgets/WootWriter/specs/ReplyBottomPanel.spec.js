import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ReplyBottomPanel from '../ReplyBottomPanel.vue';
import RecordingBar from '../RecordingBar.vue';
import ComposerOverflowMenu from '../ComposerOverflowMenu.vue';

describe('composer toolbar', () => {
  let wrapper;
  let observers;
  let phone;
  beforeEach(() => {
    phone = false;
    observers = [];
    vi.stubGlobal(
      'matchMedia',
      vi.fn(query => ({
        matches: phone && query === '(max-width: 767px)',
        media: query,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      }))
    );
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(fn) {
          this.callback = fn;
          this.observe = vi.fn();
          this.disconnect = vi.fn();
          observers.push(this);
        }
      }
    );
    vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(
      function width() {
        return this.dataset.toolbarItem ? 32 : 0;
      }
    );
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });
  const render = (props = {}) =>
    mount(ReplyBottomPanel, {
      props: {
        conversationId: 1,
        portalSlug: 'help',
        showFileUpload: true,
        showAudioRecorder: true,
        inbox: { channel_type: 'Channel::Whatsapp' },
        enableWhatsAppTemplates: true,
        sendButtonText: 'Send',
        ...props,
      },
      global: {
        plugins: [
          createStore({
            getters: {
              getCurrentAccountId: () => 1,
              'accounts/isFeatureEnabledonAccount': () => () => true,
              getUISettings: () => ({}),
            },
          }),
        ],
        mocks: { $t: key => key },
        stubs: {
          NextButton: false,
          RequestContactInfoButton: { template: '<button>Contact</button>' },
          VideoCallButton: true,
        },
      },
    });

  it('orders eligible tools and lists exactly the hidden ones, retaining FileUpload', async () => {
    wrapper = render();
    await flushPromises();
    observers
      .find(
        observer =>
          observer.observe.mock.calls[0]?.[0] ===
          wrapper.get('.left-wrap').element
      )
      .callback([{ contentRect: { width: 400 } }]);
    await flushPromises();
    expect(wrapper.findComponent(ComposerOverflowMenu).exists()).toBe(false);
    expect(
      wrapper
        .findAll('[data-toolbar-item]')
        .map(item => item.attributes('data-toolbar-item'))
    ).toEqual([
      'attach',
      'template',
      'audio',
      'emoji',
      'contact',
      'canned',
      'article',
      'signature',
    ]);
    const input = wrapper.get('input[type="file"]').element;
    observers
      .find(
        observer =>
          observer.observe.mock.calls[0]?.[0] ===
          wrapper.get('.left-wrap').element
      )
      .callback([{ contentRect: { width: 32 } }]);
    await flushPromises();
    expect(wrapper.get('input[type="file"]').element).toBe(input);
    expect(
      wrapper
        .findComponent(ComposerOverflowMenu)
        .props('items')
        .map(item => item.key)
    ).toEqual([
      'attach',
      'template',
      'audio',
      'emoji',
      'contact',
      'canned',
      'article',
      'signature',
    ]);
    wrapper.findComponent(ComposerOverflowMenu).vm.$emit('select', 'canned');
    expect(wrapper.emitted('selectCannedResponse')).toHaveLength(1);
  });

  it('swaps mic for Send only on phone with text or attachments', async () => {
    phone = true;
    const toggleAudioRecorder = vi.fn();
    wrapper = render({ toggleAudioRecorder });
    await flushPromises();
    expect(wrapper.find('[data-toolbar-item="audio"]').exists()).toBe(false);
    await wrapper.get('.right-wrap button').trigger('click');
    expect(toggleAudioRecorder).toHaveBeenCalledOnce();
    await wrapper.setProps({ message: 'Hello' });
    expect(wrapper.get('.right-wrap button').attributes('aria-label')).toBe(
      'Send'
    );
    await wrapper.setProps({ message: '', hasAttachments: true });
    expect(wrapper.get('.right-wrap button').attributes('aria-label')).toBe(
      'Send'
    );
  });

  it('keeps labelled Send and toolbar mic on desktop', async () => {
    wrapper = render();
    await flushPromises();
    expect(wrapper.find('[data-toolbar-item="audio"]').exists()).toBe(true);
    expect(wrapper.get('.right-wrap').text()).toContain('Send');
    expect(wrapper.find('kbd').exists()).toBe(true);
  });

  it.each([
    [false, 'Channel::Whatsapp'],
    [true, 'Channel::TwilioSms'],
  ])(
    'makes the template the main phone action with content templates %s',
    async (content, channelType) => {
      phone = true;
      wrapper = render({
        inbox: { channel_type: channelType, medium: 'whatsapp' },
        isEditorDisabled: true,
        isSendDisabled: true,
        enableContentTemplates: content,
      });
      await wrapper.get('.right-wrap button').trigger('click');
      expect(
        wrapper.emitted(
          content ? 'selectContentTemplate' : 'selectWhatsappTemplate'
        )
      ).toHaveLength(1);
      expect(wrapper.find('[data-toolbar-item="template"]').exists()).toBe(
        false
      );
      expect(wrapper.get('.right-wrap button').text()).toBe(
        'CONVERSATION.REPLYBOX.SEND_TEMPLATE'
      );
      expect(wrapper.find('[data-toolbar-item="contact"]').exists()).toBe(true);
      expect(wrapper.get('.left-wrap').classes()).toContain('max-md:grow-0');
      expect(wrapper.get('.right-wrap').classes()).toContain('max-md:flex-1');
      expect(wrapper.get('.right-wrap button').classes()).toContain(
        'max-md:w-full'
      );
    }
  );

  it('keeps API Send disabled without a template action', () => {
    wrapper = render({
      inbox: { channel_type: 'Channel::Api' },
      isEditorDisabled: true,
      isSendDisabled: true,
      enableWhatsAppTemplates: false,
    });
    expect(
      wrapper.get('.right-wrap button').attributes('disabled')
    ).toBeDefined();
  });

  it('replaces the row during recording and cancels through the discard handler', async () => {
    const cancel = vi.fn();
    const send = vi.fn();
    wrapper = render({
      isRecordingAudio: true,
      toggleAudioRecorder: cancel,
      onSend: send,
      recordingAudioDurationText: '00:12',
    });
    expect(wrapper.find('.left-wrap').isVisible()).toBe(false);
    const recording = wrapper.getComponent(RecordingBar);
    expect(recording.findAll('button')).toHaveLength(3);
    expect(recording.text()).toContain('00:12');
    await recording.get('button').trigger('click');
    expect(cancel).toHaveBeenCalledOnce();
    expect(send).not.toHaveBeenCalled();
  });

  it.each([
    ['', 'i-ph-stop'],
    ['stopped', 'i-ph-play'],
    ['paused', 'i-ph-play'],
    ['playing', 'i-ph-pause'],
  ])(
    'keeps playback and Send in the recording row for %s',
    async (state, icon) => {
      const playPause = vi.fn();
      const send = vi.fn();
      wrapper = render({
        isRecordingAudio: true,
        recordingAudioState: state,
        recordingAudioDurationText: '',
        toggleAudioRecorderPlayPause: playPause,
        onSend: send,
      });
      const recording = wrapper.getComponent(RecordingBar);
      expect(recording.text()).toContain('00:00');
      expect(recording.props('playStopIcon')).toBe(icon);
      const buttons = recording.findAll('button');
      await buttons[1].trigger('click');
      expect(playPause).toHaveBeenCalledOnce();
      await buttons[2].trigger('click');
      expect(send).toHaveBeenCalledOnce();
      await wrapper.setProps({ isSendDisabled: true });
      await buttons[2].trigger('click');
      expect(send).toHaveBeenCalledOnce();
    }
  );
});
