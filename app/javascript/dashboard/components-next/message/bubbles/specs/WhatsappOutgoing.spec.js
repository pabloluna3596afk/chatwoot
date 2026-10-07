import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import messages from 'dashboard/i18n/locale/en/conversation.json';
import WhatsappFlowSent from '../WhatsappFlowSent.vue';
import WhatsappTemplate from '../WhatsappTemplate.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => ref([]) }));

const mountBubble = (component, payload) => {
  const converted = useCamelCase(payload, { deep: true });
  const Host = defineComponent({
    components: { Component: component },
    setup() {
      provideMessageContext({
        content: ref(converted.content || 'Message body'),
        contentAttributes: ref(converted.contentAttributes || {}),
        additionalAttributes: ref(converted.additionalAttributes || {}),
        attachments: ref(converted.attachments || []),
        variant: ref('agent'),
      });
    },
    template: '<Component />',
  });
  return mount(Host, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      directives: {
        dompurifyHtml: (el, binding) => {
          el.textContent = binding.value;
        },
      },
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        AttachmentChips: true,
      },
    },
  });
};

describe('outgoing WhatsApp bubbles', () => {
  it.each(['Your appointment', undefined])(
    'shows Flow identity, body and informative CTA with header %s',
    header => {
      const wrapper = mountBubble(WhatsappFlowSent, {
        additional_attributes: {
          whatsapp_flow: { name: 'Schedule', header, cta: 'Open' },
        },
      });
      expect(wrapper.text()).toContain('Flow \u00b7 Schedule');
      expect(wrapper.text()).toContain('Message body');
      expect(wrapper.text()).toContain('Open');
      if (header) expect(wrapper.text()).toContain(header);
      expect(wrapper.findAll('button, a')).toHaveLength(0);
    }
  );

  it('shows template header, footer, category and all informative button types', () => {
    const wrapper = mountBubble(WhatsappTemplate, {
      content_attributes: {
        whatsapp_template: {
          name: 'confirm',
          category: 'UTILITY',
          header: { text: 'Appointment' },
          footer: 'Thank you',
          buttons: [
            { type: 'QUICK_REPLY', text: 'Confirm' },
            { type: 'QUICK_REPLY', text: 'Reschedule' },
            { type: 'URL', text: 'Location' },
            { type: 'FLOW', text: 'Open Flow' },
          ],
        },
      },
    });
    [
      'Template \u00b7 confirm',
      'UTILITY',
      'Appointment',
      'Thank you',
      'Confirm',
      'Reschedule',
      'Location',
      'Open Flow',
    ].forEach(text => {
      expect(wrapper.text()).toContain(text);
    });
    expect(wrapper.findAll('button, a')).toHaveLength(0);
  });

  it('renders the stored image header and keeps the body in the same bubble', () => {
    const wrapper = mountBubble(WhatsappTemplate, {
      content_attributes: {
        whatsapp_template: { name: 'photo', header: { format: 'IMAGE' } },
      },
      attachments: [{ id: 7, file_type: 'image', data_url: '/test-image.png' }],
    });
    expect(wrapper.get('img').attributes('src')).toBe('/test-image.png');
    expect(wrapper.text()).toContain('Message body');
    expect(
      wrapper.findComponent({ name: 'AttachmentChips' }).props('attachments')
    ).toEqual([]);
  });

  it('renders historical identity and saved buttons while omitting an unknown category', () => {
    const wrapper = mountBubble(WhatsappTemplate, {
      additional_attributes: {
        template_params: { name: 'legacy', category: 'SHIPPING_UPDATE' },
      },
      content_attributes: {
        template_buttons: [{ type: 'URL', text: 'Track' }],
      },
    });
    expect(wrapper.text()).toContain('Template \u00b7 legacy');
    expect(wrapper.text()).toContain('Track');
    expect(wrapper.text()).not.toContain('SHIPPING_UPDATE');
  });
});
