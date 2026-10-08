import { flushPromises, mount } from '@vue/test-utils';
import { KeepAlive, h } from 'vue';
import Index from '../Index.vue';
import TemplatesTable from '../TemplatesTable.vue';
import TemplateRowActions from '../TemplateRowActions.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';

const { openForm, openPreview, openSystemCopy } = vi.hoisted(() => ({
  openForm: vi.fn(),
  openPreview: vi.fn(),
  openSystemCopy: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false, locale: { value: 'en' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: false }),
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue(true) }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => true }),
}));
vi.mock('dashboard/composables/useWhatsAppTemplateSync', () => ({
  useWhatsAppTemplateSync: () => ({
    whatsappInboxes: {
      value: [
        {
          id: 7,
          name: 'Support',
          provider: 'whatsapp_cloud',
          channel_type: 'Channel::Whatsapp',
        },
      ],
    },
    canSync: true,
    isSyncing: false,
    syncTemplates: vi.fn(),
  }),
}));
vi.mock('dashboard/api/inboxes', () => ({
  default: { getMessageTemplates: vi.fn() },
}));
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: { createTemplate: vi.fn() },
}));
vi.mock('../TemplateFormDrawer.vue', () => ({
  default: { template: '<div/>', methods: { open: openForm, openSystemCopy } },
}));
vi.mock('../TemplatePreviewDrawer.vue', () => ({
  default: { template: '<div/>', methods: { open: openPreview } },
}));
vi.mock('../PresetsPanel.vue', () => ({ default: { template: '<div/>' } }));
vi.mock('../flows/FlowsPanel.vue', () => ({ default: { template: '<div/>' } }));
vi.mock('../../SettingsLayout.vue', () => ({
  default: {
    template:
      '<div><slot name="header"/><slot name="preBody"/><slot name="body"/><slot/></div>',
  },
}));
vi.mock('../../components/BaseSettingsHeader.vue', () => ({
  default: {
    template:
      '<header><slot name="title"/><slot name="tabs"/><slot name="count"/></header>',
  },
}));

describe('Templates page', () => {
  const render = async () => {
    InboxesAPI.getMessageTemplates.mockResolvedValue({
      data: {
        payload: Array.from({ length: 1000 }, (_, i) => ({
          id: String(i),
          name: `template_${i}`,
          language: 'en',
          category: i % 2 ? 'MARKETING' : 'UTILITY',
          status: 'APPROVED',
          components: [{ type: 'BODY', text: 'Hello' }],
        })),
      },
    });
    const wrapper = mount(
      { render: () => h(KeepAlive, null, { default: () => h(Index) }) },
      { global: { mocks: { $t: key => key, $te: () => false } } }
    );
    await flushPromises();
    return wrapper;
  };

  it('renders only a client page and resets pagination for combinable filters', async () => {
    const wrapper = await render();
    const table = wrapper.findComponent(TemplatesTable);
    expect(table.props('items')).toHaveLength(10);
    expect(table.props('total')).toBe(1000);
    table.vm.$emit('update:page', 2);
    await flushPromises();
    expect(table.props('page')).toBe(2);
    table.vm.$emit('update:pageSize', 25);
    await flushPromises();
    expect(table.props('items')).toHaveLength(25);
    expect(table.props('page')).toBe(1);
    const filters = wrapper.findAllComponents(FilterDropdown);
    expect(filters[3].props('options').map(option => option.count)).toEqual([
      1000, 500, 500, 0,
    ]);
    filters[3].vm.$emit('update:modelValue', 'MARKETING');
    filters[1].vm.$emit('update:modelValue', 'en');
    await flushPromises();
    expect(table.props('total')).toBe(500);
    expect(table.props('items')).toHaveLength(25);
    expect(wrapper.get('header').text()).not.toContain(
      'WHATSAPP_TEMPLATE_MGMT.COUNT'
    );
    expect(table.props('columns').map(column => column.label)).toContain(
      'WHATSAPP_TEMPLATE_MGMT.TABLE.INBOX'
    );
    wrapper.unmount();
  });

  it('opens a copy in create mode without sending anything to Meta', async () => {
    const wrapper = await render();
    const actions = wrapper.findComponent(TemplateRowActions);
    await actions.get('[data-action="duplicate"]').trigger('click');
    expect(openForm).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        name: 'template_0_copia',
        language: 'en',
        inboxId: 7,
        category: 'UTILITY',
        body: expect.objectContaining({ text: 'Hello' }),
      })
    );
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('opens the system mapping view from Duplicate for a positional template', async () => {
    const wrapper = await render();
    const table = wrapper.findComponent(TemplatesTable);
    const template = {
      ...table.props('items')[0],
      parameter_format: 'POSITIONAL',
    };
    // Row actions forward the source template to the shared drawer entry point.
    const actions = wrapper.findComponent(TemplateRowActions);
    table.props('items')[0].parameter_format = 'POSITIONAL';
    await actions.get('[data-action="duplicate"]').trigger('click');
    expect(openSystemCopy).toHaveBeenCalledWith(
      expect.objectContaining({
        name: template.name,
        parameter_format: 'POSITIONAL',
      })
    );
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uses the toolbar create slot and opens preview from a row', async () => {
    const wrapper = await render();
    expect(wrapper.findAll('[data-testid="page-create"]')).toHaveLength(1);
    expect(
      wrapper.get('header').find('[data-testid="page-create"]').exists()
    ).toBe(false);
    await wrapper.get('[data-testid="page-create"]').trigger('click');
    expect(openForm).toHaveBeenCalled();
    await wrapper.get('tbody tr').trigger('click');
    expect(openPreview).toHaveBeenCalled();
    expect(wrapper.find('[data-action="view"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
