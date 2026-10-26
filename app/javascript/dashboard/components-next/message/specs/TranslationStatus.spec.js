import { flushPromises, mount } from '@vue/test-utils';
import TranslationStatus from '../TranslationStatus.vue';
import MessageApi from 'dashboard/api/inbox/message';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/api/inbox/message', () => ({
  default: { autoTranslate: vi.fn() },
}));

describe('TranslationStatus', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the pending message state', () => {
    const wrapper = mount(TranslationStatus, {
      props: { status: 'pending', conversationId: 42, messageId: 7 },
    });

    expect(wrapper.text()).toContain('CONVERSATION.TRANSLATION_STATUS.PENDING');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('shows failure and retries the message when allowed', async () => {
    MessageApi.autoTranslate.mockResolvedValue({});
    const wrapper = mount(TranslationStatus, {
      props: {
        status: 'failed',
        conversationId: 42,
        messageId: 7,
        canRetry: true,
      },
    });

    expect(wrapper.text()).toContain('CONVERSATION.TRANSLATION_STATUS.FAILED');
    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(MessageApi.autoTranslate).toHaveBeenCalledWith(42, [7]);
  });

  it('does not show retry for messages that cannot be retried', () => {
    const wrapper = mount(TranslationStatus, {
      props: { status: 'failed', conversationId: 42, messageId: 7 },
    });

    expect(wrapper.find('button').exists()).toBe(false);
  });
});
