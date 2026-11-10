import 'dashboard/api/variables';

import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import SendCenter from '../SendCenter.vue';
import { lastSendCenterTab } from '../session';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import API from 'dashboard/api/whatsappFlows';
import en from 'dashboard/i18n/locale/en/whatsappTemplates.json';
import es from 'dashboard/i18n/locale/es/whatsappTemplates.json';
import esFlows from 'dashboard/i18n/locale/es/whatsappFlows.json';

vi.mock('dashboard/api/variables', () => ({
  default: { catalog: vi.fn(async () => ({ data: { variables: [] } })) },
}));
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
    '<div><slot name="preview" header="Header" body="Preview body" /></div>',
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
    Element.prototype.scrollIntoView = vi.fn();
    lastSendCenterTab.value = 0;
    globalOptions = {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'es',
          fallbackLocale: 'en',
          messages: { es: { ...es, ...esFlows }, en },
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

  it('keeps the selected name accessible without a repeated visual heading', async () => {
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
        templates: [
          ...templates,
          { ...templates[1], name: 'test_marketing_bienvenida' },
        ],
        sendTemplate: vi.fn(),
      },
      global: globalOptions,
    });
    await flushPromises();
    const row = wrapper.get(
      '[data-testid="center-row-template:test_marketing_bienvenida:es"]'
    );
    expect(
      row.get('[title="test_marketing_bienvenida"]').findAll('wbr')
    ).toHaveLength(2);
    await row.trigger('click');
    expect(
      wrapper.get('[data-testid="center-detail"]').attributes('aria-label')
    ).toBe('test_marketing_bienvenida');
    expect(wrapper.find('[data-testid="center-detail"] h3').exists()).toBe(
      false
    );
    expect(
      wrapper
        .find('[data-testid="center-detail"] [data-testid="template-category"]')
        .exists()
    ).toBe(false);
    expect(wrapper.get('[data-testid="center-selection"]').text()).toBe(
      'Selected template: test_marketing_bienvenida'
    );
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="center-detail"]').attributes('aria-label')
    ).toBe('Contact');
    expect(wrapper.get('[data-testid="center-selection"]').text()).toBe(
      'Selected Flow: Contact'
    );
  });

  it('clears query, filters and chips independently and announces matching results', async () => {
    wrapper = mount(SendCenter, {
      attachTo: document.body,
      props: {
        show: true,
        inbox: { id: 3, channel_type: 'Channel::Api' },
        conversationId: 5,
        canReply: true,
        templates,
        sendTemplate: vi.fn(),
      },
      global: globalOptions,
    });
    await flushPromises();
    expect(wrapper.get('[data-testid="center-count"]').text()).toBe(
      '3 plantillas'
    );
    const input = wrapper.get('[data-testid="center-search"] input');
    await input.setValue('Discount');
    expect(wrapper.get('[data-testid="center-count"]').text()).toContain(
      '1 resultado'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'offer'
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).not.toContain(
      'appointment'
    );
    const event = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
      cancelable: true,
    });
    input.element.dispatchEvent(event);
    await flushPromises();
    expect(event.defaultPrevented).toBe(true);
    expect(input.element.value).toBe('');
    expect(wrapper.emitted('close')).toBeUndefined();
    const filters = wrapper.findAllComponents(FilterDropdown);
    filters[0].vm.$emit('update:modelValue', 'template:MARKETING');
    filters[1].vm.$emit('update:modelValue', 'APPROVED');
    await flushPromises();
    expect(wrapper.get('[data-testid="center-filter-count"]').text()).toBe('2');
    expect(
      wrapper.get('[data-testid="center-filter-chips"]').findAll('button')
    ).toHaveLength(2);
    await wrapper
      .get('[data-testid="center-filter-chips"] button')
      .trigger('click');
    expect(wrapper.get('[data-testid="center-filter-count"]').text()).toBe('1');
    const toggle = wrapper.get('[data-testid="center-filter-toggle"]');
    await toggle.trigger('click');
    expect(wrapper.find('[data-testid="center-filter-chips"]').exists()).toBe(
      false
    );
    await input.setValue('no match');
    await wrapper.get('[data-testid="center-clear-filters"]').trigger('click');
    expect(input.element.value).toBe('no match');
    expect(wrapper.get('[data-testid="center-count"]').text()).toBe(
      'Sin resultados'
    );
    await input.setValue('');
    await filters[0].get('button').trigger('keydown', { key: 'Escape' });
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(toggle.element);
    await input.setValue('no match');
    await wrapper.get('[data-testid="center-list"] button').trigger('click');
    expect(input.element.value).toBe('');
    expect(wrapper.get('[data-testid="center-count"]').text()).toBe(
      '3 plantillas'
    );
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith({
      block: 'nearest',
      behavior: 'instant',
    });
  });

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
    expect(toolbar.classes()).toContain('justify-between');
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
    expect(filterRow.attributes('style')).toContain('display: none');
    await wrapper.get('[data-testid="center-filter-toggle"]').trigger('click');
    expect(filterRow.attributes('style') || '').not.toContain('display: none');
    const filters = wrapper.findAllComponents(FilterDropdown);
    expect(filters.map(filter => filter.get('button').text())).toEqual([
      'Categor\u00eda',
      'Estado',
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

  it('stops the template loading indicator while background Flows finish', async () => {
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
    expect(refresh.find('.animate-spin').exists()).toBe(false);
    resolveFlows({ data: { payload: [], can_reply: true } });
    await flushPromises();
    expect(refresh.attributes('disabled')).toBeUndefined();
    expect(refresh.find('.animate-spin').exists()).toBe(false);
  });

  it('keeps two columns and the same dialog width while customizing a Flow', async () => {
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
    const before = body.attributes('class');
    expect(wrapper.findComponent(DialogStub).attributes('width')).toBe(
      'sendCenter'
    );
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(body.attributes('data-columns')).toBe('2');
    expect(body.attributes('class')).toBe(before);
    expect(body.attributes('class')).not.toContain('dialog:has');
    expect(wrapper.get('[data-testid="center-list"]').isVisible()).toBe(true);
    await wrapper
      .get('[data-testid="flow-send-close-customize"]')
      .trigger('click');
    expect(body.attributes('class')).toBe(before);
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
    'edits body variables in the real bubble with two stable columns on %j',
    async (inbox, template) => {
      wrapper = mount(SendCenter, {
        attachTo: document.body,
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
      ).toBe('2');
      const input = wrapper.get('[data-testid="editable-body"] textarea');
      expect(
        wrapper
          .get('[data-testid="send-center-preview-body"]')
          .element.contains(input.element)
      ).toBe(true);
      expect(wrapper.get('[data-testid="center-list"]').isVisible()).toBe(true);
      expect(
        wrapper.get('[data-testid="center-invalid-reason"]').text()
      ).toContain('Falta 1 dato');
      await input.setValue('Ana');
      expect(input.element.value).toBe('Ana');
      expect(
        wrapper.get('[data-testid="center-send"]').attributes('disabled')
      ).toBeUndefined();
      await input.trigger('keydown', { key: 'Enter' });
      expect(document.activeElement).toBe(
        wrapper.get('[data-testid="center-send"]').element
      );
      await wrapper.get('[data-testid="center-send"]').trigger('click');
      await flushPromises();
      expect(wrapper.props('sendTemplate')).toHaveBeenCalledWith(
        expect.objectContaining({
          message:
            inbox.channel_type === 'Channel::TwilioSms'
              ? 'Hello Ana'
              : 'Hello {{1}}',
          templateParams: expect.objectContaining({
            name: 'editable',
            language: 'es',
            processed_params:
              inbox.channel_type === 'Channel::TwilioSms'
                ? { 1: 'Ana' }
                : { body: { 1: 'Ana' } },
          }),
        })
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
            fallbackLocale: 'en',
            messages: { es: { ...es, ...esFlows }, en },
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
            fallbackLocale: 'en',
            messages: { es: { ...es, ...esFlows }, en },
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
            fallbackLocale: 'en',
            messages: { es: { ...es, ...esFlows }, en },
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
            fallbackLocale: 'en',
            messages: { es: { ...es, ...esFlows }, en },
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

  it('keeps status in list rows and gives Flows an accessible name without a repeated title', async () => {
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
      'Sin enviar'
    );
    const detail = wrapper.get('[data-testid="center-detail"]');
    expect(detail.text()).not.toContain('Publicado');
    expect(detail.find('h3').exists()).toBe(false);
    expect(detail.attributes('aria-label')).toBe('Contact');
    expect(detail.classes()).toContain('flex-col');
    expect(wrapper.get('[data-testid="center-columns"]').classes()).toContain(
      'md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]'
    );
    await wrapper.get('[data-testid="flow-send-customize"]').trigger('click');
    expect(
      wrapper.get('[data-testid="flow-send-fields-column"]').element
        .parentElement
    ).toBe(
      wrapper.get('[data-testid="flow-send-preview-column"]').element
        .parentElement
    );
    expect(wrapper.get('[data-testid="center-ready"]').text()).toBe(
      'Listo para enviar'
    );
  });

  it('distinguishes no search results from an empty catalog and offers recovery', async () => {
    const sync = vi.fn();
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: { id: 3, channel_type: 'Channel::Api' },
        conversationId: 5,
        canReply: true,
        templates: [templates[1]],
        sendTemplate: vi.fn(),
      },
      global: {
        ...globalOptions,
        plugins: [
          ...globalOptions.plugins,
          createStore({
            getters: {
              'attributes/getAttributes': () => [],
              getSelectedChat: () => ({}),
              getCurrentUser: () => ({}),
            },
            actions: { 'inboxes/syncTemplates': sync },
          }),
        ],
      },
    });
    await flushPromises();
    await wrapper
      .get('[data-testid="center-search"] input')
      .setValue('no-match');
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.EMPTY
    );
    await wrapper.get('[data-testid="center-list"] button').trigger('click');
    expect(
      wrapper
        .find('[data-testid="center-row-template:appointment:es"]')
        .exists()
    ).toBe(true);
    await wrapper.setProps({ templates: [] });
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.EMPTY_CATALOG
    );
    await wrapper.get('[data-testid="center-list"] button').trigger('click');
    expect(sync).toHaveBeenCalledWith(expect.anything(), 3);
  });

  it('shows a language chip and snippet, hides ready status and counts active filters', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: { id: 3, channel_type: 'Channel::Api' },
        conversationId: 5,
        canReply: true,
        templates,
        sendTemplate: vi.fn(),
      },
      global: globalOptions,
    });
    await flushPromises();
    const row = wrapper.get(
      '[data-testid="center-row-template:appointment:es"]'
    );
    expect(row.text()).toContain('ES');
    expect(row.text()).toContain('Your appointment');
    expect(row.text()).not.toContain(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.STATUS.APPROVED
    );
    const filters = wrapper.findAllComponents(FilterDropdown);
    filters[0].vm.$emit('update:modelValue', 'template:UTILITY');
    filters[1].vm.$emit('update:modelValue', 'APPROVED');
    await flushPromises();
    expect(wrapper.get('[data-testid="center-filter-toggle"]').text()).toBe(
      'Filtros2'
    );
  });

  it('summarizes missing data and restores ready status after inline editing', async () => {
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::Whatsapp',
          provider: '360dialog',
        },
        conversationId: 5,
        canReply: true,
        templates: [
          {
            name: 'order',
            language: 'es_ES',
            status: 'APPROVED',
            category: 'UTILITY',
            components: [
              {
                type: 'BODY',
                text: 'Hello {{name}}, {{date}}, {{time}}, {{order}}',
              },
            ],
          },
        ],
        sendTemplate: vi.fn(),
      },
      global: { ...globalOptions, stubs: { Dialog: DialogStub } },
    });
    await flushPromises();
    expect(wrapper.get('[data-testid="center-invalid-reason"]').text()).toBe(
      'Faltan 4 datos'
    );
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeDefined();
    const fields = wrapper.findAll('[data-testid="editable-body"] textarea');
    await fields[0].setValue('Ana');
    expect(wrapper.get('[data-testid="center-invalid-reason"]').text()).toBe(
      'Faltan 3 datos'
    );
    await Promise.all(fields.slice(1).map(field => field.setValue('Value')));
    expect(wrapper.get('[data-testid="center-ready"]').text()).toBe(
      'Listo para enviar'
    );
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('isolates pending and failed Flow catalogs and retries inside the Flow tab', async () => {
    let rejectFlows;
    API.conversationFlows.mockImplementationOnce(
      () =>
        new Promise((resolve, reject) => {
          rejectFlows = reject;
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
      global: globalOptions,
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.LOADING
    );
    expect(
      wrapper
        .get('[data-testid="center-refresh"]')
        .find('.animate-spin')
        .exists()
    ).toBe(false);
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    expect(wrapper.text()).toContain(es.WHATSAPP_TEMPLATES.SEND_CENTER.LOADING);
    rejectFlows(new Error('offline'));
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      es.WHATSAPP_TEMPLATES.SEND_CENTER.LOADING
    );
    expect(wrapper.get('[data-testid="center-flow-error"]').text()).toContain(
      'No se pudo cargar'
    );
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 0 });
    await flushPromises();
    expect(wrapper.find('[data-testid="center-flow-error"]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-testid="center-footer"]').text()).not.toContain(
      'No se pudo cargar'
    );
    expect(
      wrapper.get('[data-testid="center-send"]').attributes('disabled')
    ).toBeUndefined();
    wrapper.findComponent(TabBar).vm.$emit('tabChanged', { index: 1 });
    await flushPromises();
    await wrapper
      .get('[data-testid="center-flow-error"] button')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="center-flow-error"]').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-testid="center-list"]').text()).toContain(
      'Contact'
    );
  });

  it.each([
    [{ body_text: [['Ana', '12 de noviembre']] }, '1', '2'],
    [
      {
        body_text_named_params: [
          { param_name: 'name', example: 'Ana' },
          { param_name: 'date', example: '12 de noviembre' },
        ],
      },
      'name',
      'date',
    ],
  ])(
    'uses body examples only as hints, with accessible labels and a fallback',
    async (example, first, second) => {
      wrapper = mount(SendCenter, {
        props: {
          show: true,
          inbox: {
            id: 3,
            channel_type: 'Channel::Whatsapp',
            provider: '360dialog',
          },
          conversationId: 5,
          canReply: true,
          templates: [
            {
              name: 'sample',
              status: 'APPROVED',
              language: 'es',
              category: 'UTILITY',
              components: [
                {
                  type: 'BODY',
                  text: `Hi {{${first}}}}, {{${second}}}, {{3}}`,
                  example,
                },
              ],
            },
          ],
          sendTemplate: vi.fn(),
        },
        global: { ...globalOptions, stubs: { Dialog: DialogStub } },
      });
      await flushPromises();
      const inputs = wrapper.findAll('[data-testid="editable-body"] textarea');
      expect(inputs[0].attributes('placeholder')).toBe('Ana');
      expect(inputs[1].attributes('placeholder')).toContain('12 de noviembre');
      expect(inputs[2].attributes('placeholder')).toBe('Dato 3');
      expect(inputs[2].attributes('aria-label')).toBe('Dato 3 de 3: Dato 3');
      expect(inputs.map(input => input.element.value)).toEqual(['', '', '']);
      expect(wrapper.findAll('[data-template-field]')).toHaveLength(3);
    }
  );

  it('edits a text header only inside the bubble and preserves its payload', async () => {
    const send = vi.fn(async () => false);
    wrapper = mount(SendCenter, {
      props: {
        show: true,
        inbox: {
          id: 3,
          channel_type: 'Channel::Whatsapp',
          provider: '360dialog',
        },
        conversationId: 5,
        canReply: true,
        templates: [
          {
            name: 'header',
            status: 'APPROVED',
            language: 'es',
            category: 'UTILITY',
            components: [
              { type: 'HEADER', format: 'TEXT', text: 'Order {{1}}' },
              { type: 'BODY', text: 'Ready' },
            ],
          },
        ],
        sendTemplate: send,
      },
      global: { ...globalOptions, stubs: { Dialog: DialogStub } },
    });
    await flushPromises();
    expect(wrapper.findAll('[data-template-fields] input')).toHaveLength(0);
    const fields = wrapper.findAll('[data-testid="editable-body"] textarea');
    expect(fields).toHaveLength(1);
    await fields[0].setValue('123');
    await wrapper.get('[data-testid="center-send"]').trigger('click');
    await flushPromises();
    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({
        templateParams: expect.objectContaining({
          processed_params: expect.objectContaining({ header: { 1: '123' } }),
        }),
      })
    );
  });

  it('keeps existing Spanish strings and falls back to English for new source keys', () => {
    const english = en.WHATSAPP_TEMPLATES.SEND_CENTER;
    const spanish = es.WHATSAPP_TEMPLATES.SEND_CENTER;
    expect(Object.keys(english)).toEqual(
      expect.arrayContaining(Object.keys(spanish))
    );
    const i18n = globalOptions.plugins[0];
    expect(
      i18n.global.t('WHATSAPP_TEMPLATES.SEND_CENTER.MISSING_COUNT', 1)
    ).toBe('Falta 1 dato');
    expect(
      i18n.global.t('WHATSAPP_TEMPLATES.SEND_CENTER.MISSING_COUNT', 6)
    ).toBe('Faltan 6 datos');
    i18n.global.locale.value = 'en';
    expect(
      i18n.global.t('WHATSAPP_TEMPLATES.SEND_CENTER.MISSING_COUNT', 1)
    ).toBe('Missing 1 detail');
    expect(
      i18n.global.t('WHATSAPP_TEMPLATES.SEND_CENTER.MISSING_COUNT', 6)
    ).toBe('Missing 6 details');
    ['CATEGORY', 'STATUS', 'REASONS', 'MEDIA_FORMATS'].forEach(key =>
      expect(Object.keys(english[key])).toEqual(Object.keys(spanish[key]))
    );
  });
});
