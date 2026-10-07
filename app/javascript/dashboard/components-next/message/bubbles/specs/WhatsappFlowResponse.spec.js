import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import messages from 'dashboard/i18n/locale/en/conversation.json';
import WhatsappFlowResponse from '../WhatsappFlowResponse.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
}));

const payload = {
  content_attributes: {
    whatsapp_flow_response: {
      full_name: 'Valentina Torres',
      interests: ['news', 'advice'],
      comments: 'Great support',
      document: [{ media_id: 'private-media' }],
      flow_token: 'hidden',
      otp_code: 'hidden',
    },
    whatsapp_flow_meta: {
      name: 'Sales',
      fields: [
        { key: 'full_name', label: 'Full name', type: 'short_text' },
        {
          key: 'interests',
          label: 'Interests',
          type: 'checkbox',
          options: [
            { id: 'news', title: 'News' },
            { id: 'advice', title: 'Advice' },
          ],
        },
        { key: 'comments', label: 'Comments', type: 'long_text' },
        { key: 'document', label: 'Document', type: 'document' },
      ],
    },
  },
};

const mountFlowResponse = (attributes = payload.content_attributes) => {
  const converted = useCamelCase(
    { content_attributes: attributes },
    {
      deep: true,
      stopPaths: ['content_attributes.whatsapp_flow_response'],
    }
  );
  const TestHost = defineComponent({
    components: { WhatsappFlowResponse },
    setup() {
      provideMessageContext({
        contentAttributes: ref(converted.contentAttributes),
        shouldGroupWithNext: ref(false),
      });
    },
    template: '<WhatsappFlowResponse />',
  });
  return mount(TestHost, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        MessageMeta: true,
      },
    },
  });
};

describe('WhatsappFlowResponse', () => {
  it('renders the real flat payload, original keys, option titles and files without links', () => {
    const wrapper = mountFlowResponse();
    expect(wrapper.text()).toContain('Flow \u00b7 Sales');
    expect(wrapper.findAll('dt').map(item => item.text())).toEqual([
      'Full name',
      'Interests',
      'Comments',
      'Document',
    ]);
    expect(wrapper.findAll('dd').map(item => item.text())).toEqual([
      'Valentina Torres',
      'NewsAdvice',
      'Great support',
      'File received',
    ]);
    expect(wrapper.text()).not.toContain('hidden');
    expect(wrapper.text()).not.toContain('private-media');
    expect(wrapper.findAll('a')).toHaveLength(0);
  });

  it('copies exact plain text with the Flow name and shows existing alert feedback', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = mountFlowResponse();
    await wrapper.get('[data-testid="flow-response-copy"]').trigger('click');
    expect(writeText).toHaveBeenCalledWith(
      'Sales\nFull name: Valentina Torres\nInterests: News, Advice\nComments: Great support\nDocument: File received'
    );
    expect(useAlert).toHaveBeenCalledWith('Copied');
  });

  it('uses a generic Flow header and humanized labels without metadata', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = mountFlowResponse({
      whatsapp_flow_response: { home_city: 'Quito' },
    });
    expect(wrapper.text()).toContain('Flow');
    expect(wrapper.get('dt').text()).toBe('Home City');
    await wrapper.get('[data-testid="flow-response-copy"]').trigger('click');
    expect(writeText).toHaveBeenCalledWith('Home City: Quito');
  });

  it('reports a clipboard failure through useAlert', async () => {
    Object.assign(navigator, {
      clipboard: { writeText: vi.fn().mockRejectedValue(new Error('Denied')) },
    });
    const wrapper = mountFlowResponse();
    await wrapper.get('[data-testid="flow-response-copy"]').trigger('click');
    expect(useAlert).toHaveBeenCalledWith('Could not copy the answers');
  });
});
