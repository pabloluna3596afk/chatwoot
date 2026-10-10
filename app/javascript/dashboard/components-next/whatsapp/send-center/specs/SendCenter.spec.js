import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import SendCenter from '../SendCenter.vue';
import { lastSendCenterTab } from '../session';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { SEND_CENTER_COLUMN_UNIT_CLASS } from '../helpers';
import API from 'dashboard/api/whatsappFlows';
import en from 'dashboard/i18n/locale/en/whatsappTemplates.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';
import esFlows from 'dashboard/i18n/locale/es/whatsappFlows.json';

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
  let globalOptions;
  beforeEach(() => {
    lastSendCenterTab.value = 0;
    globalOptions = {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'es',
          messages: { es: { ...es, ...esFlows } },
        }),
        createStore({
          getters: {
            'attributes/getAttributes': () => [1],
            getSelectedChat: () => ({}),
            getCurrentUser: () => ({}),
          },
        }),
      ],
      stubs: { Dialog: DialogStub, WhatsAppTemplateParser: ParserStub },
    };
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

  it('keeps native dialog close synchronized while a send is pending', async () => {
    let resolveSend;
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: { id: 3, channel_type: 'Channel::Api' },
        conversationId: 5,
        canReply: true,
        templates: [templates[1]],
        sendTemplate: () =>
          new Promise(resolve => {
            resolveSend = resolve;
          }),
      },
      global: globalOptions,
    });
    await flushPromises();
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    wrapper.findComponent(DialogStub).vm.$emit('close');
    expect(wrapper.emitted('close')).toHaveLength(1);
    resolveSend(false);
    await flushPromises();
  });

  it('preserves Spanish accents in the new source strings', () => {
    const labels = es.WHATSAPP_TEMPLATES.SEND_CENTER;
    expect(labels.DESCRIPTION).toContain('conversaci\u00f3n');
    expect(labels.REASONS.template_PENDING).toContain('aprobaci\u00f3n');
    expect(JSON.stringify(labels)).not.toContain('?');
  });

  it.each([
    'PENDING',
    'REJECTED',
    'PAUSED',
    'DISABLED',
    'IN_APPEAL',
    'FLAGGED',
    'LIMIT_EXCEEDED',
  ])(
    'shows the %s template preview and translated reason but cannot send it',
    async templateStatus => {
      const send = vi.fn();
      wrapper = mount(SendCenter, {
        props: {
          show: true,
          inbox: { id: 3, channel_type: 'Channel::Api' },
          conversationId: 5,
          canReply: true,
          templates: [{ ...templates[0], status: templateStatus }],
          sendTemplate: send,
        },
        global: globalOptions,
      });
      await flushPromises();
      expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
        'rejected'
      );
      expect(wrapper.get('[data-testid="center-reason"]').text()).toBe(
        es.WHATSAPP_TEMPLATES.SEND_CENTER.REASONS[`template_${templateStatus}`]
      );
      expect(
        wrapper.get('[data-testid="send-center-preview"]').text()
      ).toContain('Rejected body');
      expect(
        wrapper.get('[data-testid="center-send"]').attributes('disabled')
      ).toBeDefined();
      await wrapper.get('[data-testid="center-send"]').trigger('click');
      expect(send).not.toHaveBeenCalled();
      expect(wrapper.find('.i-lucide-layout-template').exists()).toBe(true);
    }
  );

  it.each([
    ['none', false, true, 'no_publication'],
    ['draft', false, true, 'flow_draft'],
    ['published', true, true, 'changes'],
    ['published', false, false, 'outside_window'],
    ['deprecated', false, true, 'flow_deprecated'],
    ['blocked', false, true, 'flow_blocked'],
    ['throttled', false, true, 'flow_throttled'],
  ])(
    'consults a %s Flow with changes=%s and window=%s without sending',
    async (flowStatus, changes, window, reason) => {
      API.conversationFlows.mockResolvedValue({
        data: {
          can_reply: window,
          payload: [
            {
              id: 12,
              name: 'Contact',
              categories: [],
              status: flowStatus,
              unpublished_changes: changes,
              can_send: false,
              screens: 1,
            },
          ],
        },
      });
      wrapper = mount(SendCenter, {
        props: {
          show: true,
          inbox: {
            id: 3,
            channel_type: 'Channel::Whatsapp',
            provider: 'whatsapp_cloud',
          },
          conversationId: 5,
          canReply: window,
          templates: [],
          sendTemplate: vi.fn(),
        },
        global: globalOptions,
      });
      await flushPromises();
      wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
      await flushPromises();
      expect(wrapper.get('[data-testid="center-reason"]').text()).toBe(
        es.WHATSAPP_TEMPLATES.SEND_CENTER.REASONS[reason]
      );
      // A Flow that cannot be sent has nothing to customize: no dead Personalizar button.
      expect(wrapper.find('[data-testid="flow-send-customize"]').exists()).toBe(
        false
      );
      expect(
        wrapper.get('[data-testid="center-send"]').attributes('disabled')
      ).toBeDefined();
      await wrapper.get('[data-testid="center-send"]').trigger('click');
      expect(API.sendToConversation).not.toHaveBeenCalled();
    }
  );

  it('waits for template delivery, prevents duplicate sends and remains open when delivery fails', async () => {
    let resolveSend;
    const send = vi.fn(
      () =>
        new Promise(resolve => {
          resolveSend = resolve;
        })
    );
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: { id: 3, channel_type: 'Channel::Api' },
        conversationId: 5,
        canReply: false,
        templates: [templates[1]],
        sendTemplate: send,
      },
      global: globalOptions,
    });
    await flushPromises();
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    expect(send).toHaveBeenCalledExactlyOnceWith({
      message: 'Your appointment',
      templateParams: { name: 'appointment' },
    });
    resolveSend(false);
    await flushPromises();
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it('switches between template and Flow tabs without a second send dialog', async () => {
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
      global: globalOptions,
    });
    await flushPromises();
    const toolbar = wrapper.get('[data-testid="center-toolbar"]');
    const columns = wrapper.get('[data-testid="center-columns"]');
    expect(toolbar.element.parentElement.parentElement.parentElement).toBe(
      columns.element
    );
    expect(
      wrapper.get('[data-testid="center-detail"]').element.parentElement
    ).toBe(columns.element);
    expect(toolbar.classes()).not.toContain('justify-between');
    expect(toolbar.findAll('button').map(button => button.text())).toEqual([
      'Plantillas',
      'Flows',
      '',
    ]);
    expect(
      wrapper.get('[data-testid="center-refresh"]').attributes('title')
    ).toBe('Actualizar cat\u00e1logo');
    expect(
      wrapper.get('[data-testid="center-refresh"]').attributes('aria-label')
    ).toBe('Actualizar cat\u00e1logo');
    expect(toolbar.findComponent(TabBar).exists()).toBe(true);
    expect(toolbar.find('[data-testid="center-refresh"]').exists()).toBe(true);
    const filterRow = wrapper.get('[data-testid="center-filters"]');
    expect(filterRow.findAllComponents(FilterDropdown)).toHaveLength(2);
    expect(filterRow.classes()).toContain('grid-cols-2');
    expect(
      wrapper.get('[data-testid="center-search"]').element.nextElementSibling
    ).toBe(filterRow.element);
    const filters = wrapper.findAllComponents(FilterDropdown);
    expect(filters.map(filter => filter.get('button').text())).toEqual([
      'Categor\u00edas',
      'Estados',
    ]);
    expect(
      filters.map(filter => filter.get('button').attributes('title'))
    ).toEqual(['Todas las categor\u00edas', 'Todos los estados']);
    expect(filters.map(filter => filter.props('options')[0].count)).toEqual([
      3, 3,
    ]);
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(filters.map(filter => filter.props('options')[0].count)).toEqual([
      2, 2,
    ]);
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'Contact'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'appointment'
    );
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 0 });
    await flushPromises();
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'appointment'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'Contact'
    );
    expect(filters.map(filter => filter.props('options')[0].count)).toEqual([
      3, 3,
    ]);
    expect(wrapper.findAllComponents(DialogStub)).toHaveLength(1);
  });

  it('keeps refresh spinning and disabled during template synchronization and Flow loading', async () => {
    let resolveSync;
    let resolveFlows;
    const sync = vi.fn(
      () =>
        new Promise(resolve => {
          resolveSync = resolve;
        })
    );
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
        ...globalOptions,
        plugins: [
          ...globalOptions.plugins,
          createStore({
            getters: {
              'attributes/getAttributes': () => [1],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
            actions: { 'inboxes/syncTemplates': sync },
          }),
        ],
      },
    });
    await flushPromises();
    API.conversationFlows.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFlows = resolve;
        })
    );
    const refresh = wrapper.get('[data-testid="center-refresh"]');
    await refresh.trigger('click');
    expect(refresh.attributes('disabled')).toBeDefined();
    expect(refresh.find('.animate-spin').exists()).toBe(true);
    await refresh.trigger('click');
    expect(sync).toHaveBeenCalledTimes(1);
    resolveSync();
    await flushPromises();
    expect(refresh.attributes('disabled')).toBeDefined();
    expect(refresh.find('.animate-spin').exists()).toBe(true);
    resolveFlows({ data: { payload: [], can_reply: true } });
    await flushPromises();
    expect(refresh.attributes('disabled')).toBeUndefined();
    expect(refresh.find('.animate-spin').exists()).toBe(false);
  });

  it('uses one width unit for two or three columns and shrinks again when customization closes', async () => {
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
      global: globalOptions,
    });
    await flushPromises();
    const body = wrapper.get('[data-testid="center-body"]');
    expect(body.classes()).toContain(SEND_CENTER_COLUMN_UNIT_CLASS);
    expect(body.attributes('data-columns')).toBe('2');
    expect(body.classes()).toContain(
      '[dialog:has(&)]:!w-[calc(var(--send-center-unit)+var(--phone-preview-width)+4.5rem)]'
    );
    expect(body.classes()).toContain('[dialog:has(&)]:!transition-[width]');
    expect(body.classes()).toContain(
      'motion-reduce:[dialog:has(&)]:!transition-none'
    );
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(body.attributes('data-columns')).toBe('3');
    expect(body.classes()).toContain(
      'xl:[dialog:has(&)]:!w-[calc(2*var(--send-center-unit)+var(--phone-preview-width)+6rem)]'
    );
    expect(body.classes()).toContain(
      'max-xl:[dialog:has(&)]:!w-[calc(100vw-2rem)]'
    );
    expect(
      wrapper.get('[data-testid="flow-send-preview-column"]').classes()
    ).not.toContain('max-xl:hidden');
    await wrapper
      .get('[data-testid="flow-send-close-customize"]')
      .trigger('click');
    expect(body.attributes('data-columns')).toBe('2');
  });

  it.each([
    [
      { id: 3, channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' },
      {
        name: 'editable',
        language: 'es',
        status: 'APPROVED',
        category: 'UTILITY',
        components: [{ type: 'BODY', text: 'Hello {{1}}' }],
      },
    ],
    [
      { id: 3, channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
      {
        friendly_name: 'editable',
        language: 'es',
        status: 'APPROVED',
        category: 'UTILITY',
        body: 'Hello {{1}}',
      },
    ],
  ])(
    'allocates a third unit for editable template fields on %j',
    async (inbox, template) => {
      wrapper = mount(SendCenter, {
        props: {
          show: true,
          inbox,
          conversationId: 5,
          canReply: true,
          templates: [template],
          sendTemplate: vi.fn(),
        },
        global: { ...globalOptions, stubs: { Dialog: DialogStub } },
      });
      await flushPromises();
      expect(
        wrapper.get('[data-testid="center-body"]').attributes('data-columns')
      ).toBe('3');
      expect(wrapper.get('[data-testid="center-body"]').classes()).toContain(
        'xl:[dialog:has(&)]:!w-[calc(2*var(--send-center-unit)+var(--phone-preview-width)+6rem)]'
      );
      const input = wrapper.get('[data-testid="center-detail"] input');
      await input.setValue('Ana');
      expect(wrapper.get('[data-testid="center-detail"]').text()).toContain(
        'Hello Ana'
      );
    }
  );

  it('retains each tab search, category, status and selection with counts only from that tab', async () => {
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
      global: globalOptions,
    });
    await flushPromises();
    const [categoryFilter, statusFilter] =
      wrapper.findAllComponents(FilterDropdown);
    await wrapper
      .get('[data-testid="center-search"] input')
      .setValue('appointment');
    categoryFilter.vm.$emit('update:modelValue', 'template:UTILITY');
    statusFilter.vm.$emit('update:modelValue', 'APPROVED');
    await flushPromises();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="center-search"] input').element.value
    ).toBe('');
    expect(categoryFilter.props('modelValue')).toBe('ALL');
    expect(statusFilter.props('modelValue')).toBe('ALL');
    expect(categoryFilter.props('options')[0].count).toBe(2);
    expect(statusFilter.props('options')[0].count).toBe(2);
    expect(categoryFilter.props('groups').map(group => group.key)).toEqual([
      'flows',
    ]);
    expect(
      statusFilter.props('options').some(option => option.value === 'APPROVED')
    ).toBe(false);
    expect(
      categoryFilter
        .props('options')
        .some(option => option.value.startsWith('template:'))
    ).toBe(false);
    await wrapper.get('[data-testid="center-search"] input').setValue('Draft');
    categoryFilter.vm.$emit('update:modelValue', 'flow:CONTACT_US');
    statusFilter.vm.$emit('update:modelValue', 'none');
    await flushPromises();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 0 });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="center-search"] input').element.value
    ).toBe('appointment');
    expect(categoryFilter.props('modelValue')).toBe('template:UTILITY');
    expect(statusFilter.props('modelValue')).toBe('APPROVED');
    expect(categoryFilter.props('options')[0].count).toBe(1);
    expect(
      wrapper
        .get('[data-testid="center-row-template:appointment:es"]')
        .attributes('aria-pressed')
    ).toBe('true');
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="center-search"] input').element.value
    ).toBe('Draft');
    expect(categoryFilter.props('modelValue')).toBe('flow:CONTACT_US');
    expect(statusFilter.props('modelValue')).toBe('none');
    expect(categoryFilter.props('options')[0].count).toBe(1);
    expect(
      wrapper
        .get('[data-testid="center-row-flow:13"]')
        .attributes('aria-pressed')
    ).toBe('true');
  });

  it('defaults to Plantillas, puts usable items first, and searches template content', async () => {
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
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es: { ...es, ...esFlows } },
          }),
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
    expect(
      wrapper
        .findComponent(TabBar)
        .props('tabs')
        .map(item => item.label)
    ).toEqual(['Plantillas', 'Flows']);
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'Contact'
    );
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
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es: { ...es, ...esFlows } },
          }),
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
    const [categoryFilter, statusFilter] =
      wrapper.findAllComponents(FilterDropdown);
    expect(
      categoryFilter.props('options').find(option => option.value === 'ALL')
        .count
    ).toBe(3);
    expect(
      statusFilter.props('options').find(option => option.value === 'ALL').count
    ).toBe(3);
    expect(
      categoryFilter
        .props('options')
        .find(option => option.value === 'template:AUTHENTICATION').count
    ).toBe(0);
    wrapper
      .findAllComponents(FilterDropdown)[0]
      .vm.$emit('update:modelValue', 'template:UTILITY');
    await flushPromises();
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'offer'
    );
    expect(categoryFilter.get('button').text()).toBe('Utilidad');
    expect(categoryFilter.get('button').attributes('title')).toBe('Utilidad');
    expect(
      statusFilter.props('options').find(option => option.value === 'ALL').count
    ).toBe(2);
    expect(
      statusFilter.props('options').find(option => option.value === 'APPROVED')
        .count
    ).toBe(1);
    wrapper
      .findAllComponents(FilterDropdown)[1]
      .vm.$emit('update:modelValue', 'REJECTED');
    await flushPromises();
    expect(
      categoryFilter.props('options').find(option => option.value === 'ALL')
        .count
    ).toBe(1);
    expect(
      statusFilter.props('options').find(option => option.value === 'ALL').count
    ).toBe(2);
    await wrapper
      .get('[data-testid="center-search"] input')
      .setValue('appointment');
    expect(
      categoryFilter.props('options').find(option => option.value === 'ALL')
        .count
    ).toBe(0);
    expect(
      statusFilter.props('options').find(option => option.value === 'APPROVED')
        .count
    ).toBe(1);
    await wrapper.get('[data-testid="center-search"] input').setValue('');
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
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es: { ...es, ...esFlows } },
          }),
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
    ).toEqual(['Plantillas']);
    expect(wrapper.find('.i-woot-whatsapp').exists()).toBe(true);
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
          createI18n({
            legacy: false,
            locale: 'es',
            messages: { es: { ...es, ...esFlows } },
          }),
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
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
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

  it('remembers the last tab across dialog instances without sharing filters, and keeps Twilio templates-only', async () => {
    const props = {
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
    };
    wrapper = mount(SendCenter, { props, global: globalOptions });
    await flushPromises();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    await wrapper
      .get('[data-testid="center-search"] input')
      .setValue('Contact');
    wrapper.unmount();
    wrapper = mount(SendCenter, { props, global: globalOptions });
    await flushPromises();
    expect(wrapper.findComponent(TabBar).props('initialActiveTab')).toBe(1);
    expect(
      wrapper.get('[data-testid="center-search"] input').element.value
    ).toBe('');
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 0 });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="center-search"] input').element.value
    ).toBe('');
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    wrapper.unmount();
    wrapper = mount(SendCenter, {
      props: {
        ...props,
        inbox: {
          id: 3,
          channel_type: 'Channel::TwilioSms',
          medium: 'whatsapp',
        },
      },
      global: {
        ...globalOptions,
        stubs: { Dialog: DialogStub, ContentTemplateParser: ParserStub },
      },
    });
    await flushPromises();
    expect(wrapper.findComponent(TabBar).props('initialActiveTab')).toBe(0);
    expect(lastSendCenterTab.value).toBe(1);
  });

  it('keeps invalid Flow send disabled with a reason and Esc from the footer closes only customization', async () => {
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
      global: globalOptions,
    });
    await flushPromises();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    await wrapper.get('[data-testid="flow-send-body"] textarea').setValue('');
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[data-testid="center-invalid-reason"]').text()).toBe(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.BODY_REQUIRED
    );
    await wrapper
      .get('[data-testid="center-body"]')
      .trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="flow-send-fields-column"]').exists()
    ).toBe(false);
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it('keeps status only in list rows and places the compact title above the preview without inheriting the list controls height', async () => {
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
      global: globalOptions,
    });
    await flushPromises();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'Publicado'
    );
    const detail = wrapper.get('[data-testid="center-detail"]');
    expect(detail.text()).not.toContain('Publicado');
    // The selected name already shows in the list: the detail column starts at the top, with no title.
    expect(detail.find('[data-testid="center-detail-header"]').exists()).toBe(
      false
    );
    expect(detail.classes()).toContain('flex-col');
    expect(detail.classes()).toContain('gap-6');
    expect(
      wrapper
        .get('[data-testid="center-list"]')
        .element.parentElement.classList.contains('grid-rows-subgrid')
    ).toBe(true);
    expect(wrapper.get('[data-testid="center-columns"]').classes()).toContain(
      'grid-rows-[auto_minmax(0,1fr)]'
    );
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-send-fields-column"]').element
        .parentElement
    ).toBe(
      wrapper.get('[data-testid="flow-send-preview-column"]').element
        .parentElement
    );
    expect(wrapper.text()).not.toContain('Listo para enviar');
  });

  it('ships matching English and Spanish send-center keys', () => {
    const english = en.WHATSAPP_TEMPLATES.SEND_CENTER;
    const spanish = es.WHATSAPP_TEMPLATES.SEND_CENTER;
    expect(Object.keys(english)).toEqual(Object.keys(spanish));
    ['CATEGORY', 'STATUS', 'REASONS', 'MEDIA_FORMATS'].forEach(key =>
      expect(Object.keys(english[key])).toEqual(Object.keys(spanish[key]))
    );
  });
});
