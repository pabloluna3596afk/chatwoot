import { flushPromises, mount } from '@vue/test-utils';
import { KeepAlive, h } from 'vue';
import { mockNativeDialog } from 'dashboard/helper/specs/mockNativeDialog';
import Index from '../Index.vue';
import TemplatesTable from '../TemplatesTable.vue';
import TemplateRowActions from '../TemplateRowActions.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import { ref } from 'vue';
import { draftFromForm } from '../templateDrafts';
import { emptyForm } from '../templateForm';

const { openForm, openPreview, openDuplicate, openDraft, openBindings, query } =
  vi.hoisted(() => ({
    query: {},
    openDraft: vi.fn(),
    openBindings: vi.fn(),
    openForm: vi.fn(),
    openPreview: vi.fn(),
    openDuplicate: vi.fn(),
  }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query }),
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
const role = ref(true);
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => role.value }),
}));
vi.mock('dashboard/composables/useWhatsAppTemplateSync', () => ({
  useWhatsAppTemplateSync: () => ({
    whatsappInboxes: {
      value: [
        {
          id: 7,
          channel_id: 70,
          provider_config: { business_account_id: 'waba-a' },
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
vi.mock('dashboard/api/whatsappTemplateDrafts', () => ({
  default: { get: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: { createTemplate: vi.fn() },
}));
vi.mock('../TemplateFormDrawer.vue', () => ({
  default: {
    template: '<div/>',
    methods: { open: openForm, openDuplicate, openDraft, openBindings },
  },
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
  beforeEach(() => {
    mockNativeDialog();
    role.value = true;
    DraftsAPI.get.mockResolvedValue({
      data: { payload: [], meta: { total_count: 0 } },
    });
  });
  const render = async (records = null) => {
    InboxesAPI.getMessageTemplates.mockResolvedValue({
      data: {
        payload:
          records ||
          Array.from({ length: 1000 }, (_, i) => ({
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

  it('filters pending variables, sorts utility first and offers Edit and a quiet pending indicator', async () => {
    const pending = {
      language: 'es',
      category: 'MARKETING',
      status: 'APPROVED',
      variable_sources: { body: { 1: { source: 'missing' } } },
      missing_variables: ['1'],
      components: [{ type: 'BODY', text: 'Hola {{1}}' }],
    };
    const wrapper = await render([
      { ...pending, id: '1', name: 'a_promo' },
      { ...pending, id: '2', name: 'z_utilidad', category: 'UTILITY' },
      { ...pending, id: '3', name: 'code', category: 'AUTHENTICATION' },
      { ...pending, id: '4', name: 'waiting', status: 'PENDING' },
    ]);
    const actions = wrapper.findAllComponents(TemplateRowActions);
    expect(actions[0].props('canEdit')).toBe(true);
    expect(
      wrapper.findAll('tbody [data-testid="template-pending"]')
    ).toHaveLength(2);
    await wrapper.get('button[aria-pressed]').trigger('click');
    const table = wrapper.findComponent(TemplatesTable);
    expect(table.props('items').map(item => item.name)).toEqual([
      'z_utilidad',
      'a_promo',
    ]);
    expect(table.props('columns').map(column => column.key)).not.toContain(
      'DATA'
    );
    wrapper.unmount();
  });

  it('opens the edit form from the pending-variable link', async () => {
    Object.assign(query, { q: 'pedido_listo', filter: 'missing' });
    const wrapper = await render([
      {
        id: '55',
        name: 'pedido_listo',
        language: 'es',
        status: 'APPROVED',
        category: 'UTILITY',
        components: [{ type: 'BODY', text: 'Hola {{1}}' }],
        variable_sources: { body: { 1: { source: 'missing' } } },
        missing_variables: ['1'],
      },
    ]);
    expect(openBindings).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'pedido_listo' })
    );
    delete query.q;
    delete query.filter;
    wrapper.unmount();
  });

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

  it('opens the shared duplicate workflow without creating anything in Meta', async () => {
    const wrapper = await render();
    await wrapper
      .findComponent(TemplateRowActions)
      .get('[data-action="duplicate"]')
      .trigger('click');
    expect(openDuplicate).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'template_0' })
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
    expect(openForm).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'template_0' })
    );
    expect(wrapper.find('[data-action="view"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('loads all local pages and combines status and no-channel filters', async () => {
    const local = {
      ...draftFromForm(emptyForm(), []),
      id: 31,
      lock_version: 0,
      status: 'draft',
      submissions: [],
      updated_at: '2026-11-21T01:00:00Z',
    };
    DraftsAPI.get
      .mockResolvedValueOnce({
        data: { payload: [local], meta: { total_count: 2 } },
      })
      .mockResolvedValueOnce({
        data: {
          payload: [{ ...local, id: 32, status: 'reconciling' }],
          meta: { total_count: 2 },
        },
      });
    const wrapper = await render([]);
    expect(DraftsAPI.get).toHaveBeenCalledWith(
      { page: '2', per_page: '100' },
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    const table = wrapper.findComponent(TemplatesTable);
    expect(table.props('total')).toBe(2);
    expect(table.props('columns').map(column => column.key)).toContain(
      'META_STATUS'
    );
    const status = wrapper.findComponent('[data-testid="status-filter"]');
    expect(status.props('options').map(item => item.value)).toEqual([
      'all',
      'draft',
      'submitting',
      'reconciling',
      'failed',
      'submitted',
      'PENDING',
      'APPROVED',
      'REJECTED',
      'PAUSED',
      'DISABLED',
      'IN_APPEAL',
    ]);
    status.vm.$emit('update:modelValue', 'draft');
    wrapper
      .findAllComponents(FilterDropdown)[0]
      .vm.$emit('update:modelValue', 'none');
    await flushPromises();
    expect(table.props('items').map(item => item.id)).toEqual([31]);
    table.vm.$emit('open', table.props('items')[0]);
    expect(openDraft).toHaveBeenCalledWith(expect.objectContaining({ id: 31 }));
    wrapper.unmount();
  });

  it('deletes only the local draft with the revision after confirmation', async () => {
    DraftsAPI.get.mockResolvedValue({
      data: {
        payload: [
          {
            ...draftFromForm(emptyForm(), []),
            id: 31,
            lock_version: 7,
            status: 'draft',
            submissions: [],
          },
        ],
        meta: { total_count: 1 },
      },
    });
    const wrapper = await render([]);
    await wrapper
      .findComponent(TemplateRowActions)
      .get('[data-action="delete"]')
      .trigger('click');
    await flushPromises();
    const dialog = wrapper.findComponent(Dialog);
    expect(dialog.props('title')).toBe('WHATSAPP_TEMPLATE_MGMT.DRAFTS.DELETE');
    expect(document.body.textContent).toContain('DRAFTS.DELETE_HELP');
    expect(DraftsAPI.delete).not.toHaveBeenCalled();
    dialog.vm.$emit('confirm');
    await flushPromises();
    expect(DraftsAPI.delete).toHaveBeenCalledWith(31, 7);
    wrapper.unmount();
  });

  it('shows fetch failures instead of treating them as an empty successful load', async () => {
    DraftsAPI.get.mockRejectedValue(new Error('offline'));
    const wrapper = await render([]);
    expect(useAlert).toHaveBeenCalledWith(
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.FETCH_ERROR'
    );
    wrapper.unmount();
  });

  it('does not fetch drafts or expose admin actions for agents', async () => {
    role.value = false;
    const wrapper = await render();
    expect(DraftsAPI.get).not.toHaveBeenCalled();
    expect(wrapper.findComponent(TemplateRowActions).exists()).toBe(false);
    expect(wrapper.find('[data-testid="page-create"]').exists()).toBe(false);
    await wrapper.get('tbody tr').trigger('click');
    expect(openPreview).toHaveBeenCalled();
    wrapper.unmount();
  });

  it('filters every local state independently from the Meta review states', async () => {
    const states = [
      'draft',
      'submitting',
      'reconciling',
      'failed',
      'submitted',
    ];
    DraftsAPI.get.mockResolvedValue({
      data: {
        payload: states.map((status, index) => ({
          ...draftFromForm(emptyForm(), []),
          id: index + 1,
          lock_version: 2,
          status,
          submissions:
            status === 'submitted'
              ? [{ revision: 2, remote_status: 'IN_APPEAL' }]
              : [],
        })),
        meta: { total_count: 5 },
      },
    });
    const wrapper = await render([]);
    const filter = wrapper.findComponent('[data-testid="status-filter"]');
    const table = wrapper.findComponent(TemplatesTable);
    await states.reduce(async (previous, state, index) => {
      await previous;
      filter.vm.$emit('update:modelValue', state);
      await flushPromises();
      expect(table.props('items').map(item => item.id)).toEqual([index + 1]);
    }, Promise.resolve());
    filter.vm.$emit('update:modelValue', 'IN_APPEAL');
    await flushPromises();
    expect(table.props('items').map(item => item.id)).toEqual([5]);
    wrapper.unmount();
  });

  it('reloads after a stale deletion instead of retrying with another revision', async () => {
    DraftsAPI.get.mockResolvedValue({
      data: {
        payload: [
          {
            ...draftFromForm(emptyForm(), []),
            id: 31,
            lock_version: 7,
            status: 'draft',
            submissions: [],
          },
        ],
        meta: { total_count: 1 },
      },
    });
    DraftsAPI.delete.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'stale_revision' } },
    });
    const wrapper = await render([]);
    await wrapper
      .findComponent(TemplateRowActions)
      .get('[data-action="delete"]')
      .trigger('click');
    wrapper.findComponent(Dialog).vm.$emit('confirm');
    await flushPromises();
    expect(DraftsAPI.delete).toHaveBeenCalledTimes(1);
    expect(openDraft).toHaveBeenCalledWith(expect.objectContaining({ id: 31 }));
    expect(useAlert).toHaveBeenCalledWith(
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.CONFLICT'
    );
    wrapper.unmount();
  });
});
