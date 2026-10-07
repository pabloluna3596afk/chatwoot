import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import SendCenter from '../SendCenter.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import API from 'dashboard/api/whatsappFlows';
import en from 'dashboard/i18n/locale/en/whatsappTemplates.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';

vi.mock('dashboard/api/whatsappFlows', () => ({
  default: { conversationFlows: vi.fn(), sendToConversation: vi.fn() },
}));
const templates = [
  {
    name: 'rejected',
    status: 'REJECTED',
    category: 'UTILITY',
    language: 'es',
    components: [{ type: 'BODY', text: 'Rejected body' }],
  },
  {
    name: 'appointment',
    status: 'APPROVED',
    category: 'UTILITY',
    language: 'es',
    components: [{ type: 'BODY', text: 'Your appointment' }],
  },
  {
    name: 'offer',
    status: 'APPROVED',
    category: 'MARKETING',
    language: 'es',
    components: [{ type: 'BODY', text: 'Discount' }],
  },
];
const DialogStub = {
  template: '<div><slot /><slot name="footer" /></div>',
  methods: { open() {}, close() {} },
};
const ParserStub = {
  template:
    '<div>Template parser<slot name="preview" header="Header" body="Preview body" /></div>',
  data: () => ({ isFormInvalid: false }),
  methods: {
    sendMessage() {
      this.$emit('sendMessage', {
        message: 'Your appointment',
        templateParams: { name: 'appointment' },
      });
    },
  },
};

describe('unified send center', () => {
  let wrapper;
  beforeEach(() => {
    API.conversationFlows.mockResolvedValue({
      data: {
        can_reply: true,
        payload: [
          {
            id: 12,
            name: 'Contact',
            categories: ['CONTACT_US'],
            status: 'published',
            can_send: true,
            screens: 1,
          },
          {
            id: 13,
            name: 'Draft',
            categories: ['CONTACT_US'],
            status: 'none',
            can_send: false,
            screens: 1,
          },
        ],
      },
    });
    API.sendToConversation.mockResolvedValue({});
  });
  afterEach(() => wrapper?.unmount());

  it('defaults to Todos, puts usable items first, and searches template content', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::Whatsapp',
          provider: 'whatsapp_cloud',
        },
        conversationId: 5,
        canReply: true,
        templates,
        sendTemplate: vi.fn(),
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
          createStore({
            getters: {
              'attributes/getAttributes': () => [1],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
          }),
        ],
        stubs: { Dialog: DialogStub, WhatsAppTemplateParser: ParserStub },
      },
    });
    await flushPromises();
    expect(wrapper.findComponent(TabBar).props('initialActiveTab')).toBe(0);
    expect(
      wrapper.get('[data-testid="center-list"]').findAll('button')[0].text()
    ).toContain('appointment');
    expect(wrapper.text()).toContain('Contact');
    expect(wrapper.text()).toContain('Sin publicar en esta cuenta');
    await wrapper
      .get('[data-testid="center-search"] input')
      .setValue('Discount');
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'offer'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'Contact'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'appointment'
    );
  });

  it('filters categories and statuses, explains blocked selection and keeps one Send action', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::Whatsapp',
          provider: 'whatsapp_cloud',
        },
        conversationId: 5,
        canReply: true,
        templates,
        sendTemplate: vi.fn(),
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
          createStore({
            getters: {
              'attributes/getAttributes': () => [1],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
          }),
        ],
        stubs: { Dialog: DialogStub, WhatsAppTemplateParser: ParserStub },
      },
    });
    await flushPromises();
    wrapper
      .findAllComponents(ComboBox)[0]
      .vm.$emit('update:modelValue', 'template:UTILITY');
    await flushPromises();
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'offer'
    );
    wrapper
      .findAllComponents(ComboBox)[1]
      .vm.$emit('update:modelValue', 'REJECTED');
    await flushPromises();
    expect(wrapper.get('[data-testid="center-reason"]').text()).toBe(
      'Rechazada por Meta'
    );
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.findAll('button').filter(b => b.text() === 'Enviar')
    ).toHaveLength(1);
  });

  it('has no Flows tab or API request on Twilio WhatsApp and keeps its WhatsApp icon', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::TwilioSms',
          medium: 'whatsapp',
        },
        conversationId: 5,
        canReply: false,
        templates: [
          {
            friendly_name: 'twilio',
            status: 'approved',
            body: 'Hello',
            category: 'UTILITY',
            language: 'es',
          },
        ],
        sendTemplate: vi.fn(),
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
          createStore({
            getters: {
              'attributes/getAttributes': () => [1],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
          }),
        ],
        stubs: { Dialog: DialogStub, ContentTemplateParser: ParserStub },
      },
    });
    await flushPromises();
    expect(API.conversationFlows).not.toHaveBeenCalled();
    expect(
      wrapper
        .findComponent(TabBar)
        .props('tabs')
        .map(tab => tab.label)
    ).toEqual(['Todos', 'Plantillas']);
    expect(wrapper.find('.i-ph-whatsapp-logo').exists()).toBe(true);
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('sends a Flow through the existing endpoint and retains errors without closing', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::Whatsapp',
          provider: 'whatsapp_cloud',
        },
        conversationId: 5,
        canReply: true,
        templates: [],
        sendTemplate: vi.fn(),
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { es } }),
          createStore({
            getters: {
              'attributes/getAttributes': () => [1],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
          }),
        ],
        stubs: { Dialog: DialogStub },
      },
    });
    await flushPromises();
    API.sendToConversation.mockRejectedValueOnce({
      response: { data: { error: 'Meta refused' } },
    });
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Meta refused');
    expect(wrapper.emitted('close')).toBeUndefined();
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    await flushPromises();
    expect(API.sendToConversation).toHaveBeenLastCalledWith(5, {
      whatsapp_flow_id: 12,
      header: '',
      body: 'Contact',
      cta: 'Abrir Flow',
    });
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('ships matching English and Spanish send-center keys', () => {
    const english = en.WHATSAPP_TEMPLATES.SEND_CENTER;
    const spanish = es.WHATSAPP_TEMPLATES.SEND_CENTER;
    expect(Object.keys(english)).toEqual(Object.keys(spanish));
    ['CATEGORY', 'STATUS', 'REASONS'].forEach(key =>
      expect(Object.keys(english[key])).toEqual(Object.keys(spanish[key]))
    );
  });
});
