import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import WhatsappFlowResponse from '../WhatsappFlowResponse.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountFlowResponse = () => {
  const TestHost = defineComponent({
    components: { WhatsappFlowResponse },
    setup() {
      provideMessageContext({
        content: ref('Submitted a flow response'),
        contentAttributes: ref({
          whatsappFlowResponse: {
            responseJson: {
              flow_token: 'correlation-token',
              rating: 'excellent',
              comments: 'Great support',
              appointment: { day: 'Monday' },
            },
          },
        }),
      });
    },
    template: '<WhatsappFlowResponse />',
  });

  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        CONVERSATION: {
          WHATSAPP_FLOW_RESPONSE: 'Submitted a flow response',
          WHATSAPP_FLOW_COMPLETED: 'Form completed',
          WHATSAPP_FLOW_COPY: 'Copy data',
          WHATSAPP_FLOW_COPIED: 'Data copied',
          WHATSAPP_FLOW_COPY_ERROR: 'Could not copy the data',
        },
      },
    },
  });

  return mount(TestHost, {
    global: {
      plugins: [i18n],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
      },
    },
  });
};

describe('WhatsappFlowResponse', () => {
  it('renders the submitted fields without exposing the correlation token', () => {
    const wrapper = mountFlowResponse();
    const labels = wrapper.findAll('dt').map(item => item.text());
    const values = wrapper.findAll('dd').map(item => item.text());

    expect(wrapper.text()).toContain('Form completed');
    expect(labels).toEqual(['Rating', 'Comments', 'Appointment Day']);
    expect(values).toEqual(['excellent', 'Great support', 'Monday']);
    expect(wrapper.text()).not.toContain('correlation-token');
  });

  it('copies the answers as text', async () => {
    const writeText = vi.fn().mockResolvedValue();
    Object.assign(navigator, { clipboard: { writeText } });
    const wrapper = mountFlowResponse();

    await wrapper.get('[data-testid="flow-response-copy"]').trigger('click');

    expect(writeText).toHaveBeenCalledWith(
      'Rating: excellent\nComments: Great support\nAppointment Day: Monday'
    );
  });
});
