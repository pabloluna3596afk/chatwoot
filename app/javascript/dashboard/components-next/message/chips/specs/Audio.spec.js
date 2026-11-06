import { defineComponent, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import messages from 'dashboard/i18n/locale/en/conversation.json';
import { provideMessageContext } from '../../provider.js';
import AudioChip from '../Audio.vue';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { transcribeAudio: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => ref([]) }));

const mountAudio = attachment => {
  const Host = defineComponent({
    components: { AudioChip },
    setup() {
      provideMessageContext({
        attachments: ref([]),
        conversationId: ref(42),
      });
    },
    data: () => ({ attachment }),
    template: '<AudioChip :attachment="attachment" />',
  });
  return mount(Host, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...messages, CONVERSATION: messages } },
        }),
      ],
      stubs: { Icon: true },
      directives: { tooltip: () => {} },
    },
  });
};

describe('Audio transcription button', () => {
  beforeEach(() => vi.clearAllMocks());

  it('uses translation keys defined at the conversation locale root', () => {
    expect(messages.AUDIO_TRANSCRIPTION).toEqual(
      expect.objectContaining({
        BUTTON: expect.any(String),
        ERROR: expect.any(String),
        INSUFFICIENT: expect.any(String),
        PLAN_REQUIRED: expect.any(String),
        QUOTA_EXHAUSTED: expect.any(String),
      })
    );
  });

  it('renders an icon-only button with a transcription tooltip', () => {
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: true, units: 1 },
    });
    const button = wrapper.get('button[aria-label="Transcribe audio"]');

    expect(button.text()).toBe('');
    expect(button.attributes('disabled')).toBeUndefined();
    expect(button.element.parentElement).toBe(
      wrapper.get('audio + div > div').element
    );
    expect(button.classes()).toEqual(
      expect.arrayContaining(['p-0', 'border-0', 'size-8'])
    );
    expect(button.html()).toContain('i-material-symbols-speech-to-text');
    expect(wrapper.find('[aria-hidden="true"]').exists()).toBe(false);
  });

  it.each([
    [
      { available: false, reason: 'quota_exhausted' },
      'No internal actions left this month',
    ],
    [
      { available: false, reason: 'plan_unavailable' },
      'Available on higher plans',
    ],
  ])('disables the button with a specific quota reason', (quota, tooltip) => {
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: quota,
    });
    const button = wrapper.get('button[aria-label]');

    expect(button.attributes('disabled')).toBeDefined();
    expect(button.attributes('aria-label')).toBe(tooltip);
  });

  it('hides the transcription button when the account administrator disabled it', () => {
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: false, reason: 'account_disabled' },
    });

    expect(wrapper.find('button[aria-label]').exists()).toBe(false);
  });

  it('shows a spinning loader in the player row while transcription is pending', async () => {
    let finishTranscription;
    ConversationAPI.transcribeAudio.mockReturnValue(
      new Promise(resolve => {
        finishTranscription = resolve;
      })
    );
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: true, units: 1 },
    });
    const button = wrapper.get('button[aria-label="Transcribe audio"]');

    await button.trigger('click');

    expect(button.attributes('disabled')).toBeDefined();
    expect(button.element.parentElement).toBe(
      wrapper.get('audio + div > div').element
    );
    expect(button.html()).toContain('i-lucide-loader-circle');
    expect(button.find('icon-stub').classes()).toContain('animate-spin');

    finishTranscription({ data: { transcriptions: '' } });
    await flushPromises();
  });

  it('replaces the button with the transcript after a successful request', async () => {
    ConversationAPI.transcribeAudio.mockResolvedValue({
      data: { success: true, transcriptions: 'Recognized words' },
    });
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: true, units: 1 },
    });

    await wrapper.get('button[aria-label]').trigger('click');

    expect(ConversationAPI.transcribeAudio).toHaveBeenCalledWith({
      conversationId: 42,
      attachmentId: 8,
    });
    expect(wrapper.text()).toContain('Recognized words');
    expect(wrapper.find('button[aria-label]').exists()).toBe(false);
    expect(
      wrapper.find('[aria-hidden="true"].i-lucide-sparkles').exists()
    ).toBe(true);
    expect(wrapper.find('.text-n-slate-12.p-3.pe-8').exists()).toBe(true);
  });
});
