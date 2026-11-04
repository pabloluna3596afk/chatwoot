import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
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
          messages: { en: { CONVERSATION: messages } },
        }),
      ],
      stubs: { Icon: true },
      directives: { tooltip: () => {} },
    },
  });
};

describe('Audio transcription button', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders an icon-only button with a transcription tooltip', () => {
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: true, units: 1, remaining: 4 },
    });
    const button = wrapper.get('button[aria-label="Transcribe audio"]');

    expect(button.text()).toBe('');
    expect(button.attributes('disabled')).toBeUndefined();
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

  it('replaces the button with the transcript after a successful request', async () => {
    ConversationAPI.transcribeAudio.mockResolvedValue({
      data: { success: true, transcriptions: 'Recognized words' },
    });
    const wrapper = mountAudio({
      id: 8,
      dataUrl: 'http://localhost/audio.ogg',
      transcriptionQuota: { available: true, units: 1, remaining: 4 },
    });

    await wrapper.get('button[aria-label]').trigger('click');

    expect(ConversationAPI.transcribeAudio).toHaveBeenCalledWith({
      conversationId: 42,
      attachmentId: 8,
    });
    expect(wrapper.text()).toContain('Recognized words');
    expect(wrapper.find('button[aria-label]').exists()).toBe(false);
  });
});
