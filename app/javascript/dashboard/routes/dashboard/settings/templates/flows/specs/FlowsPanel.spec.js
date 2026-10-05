import { flushPromises, mount } from '@vue/test-utils';
import FlowsPanel from '../FlowsPanel.vue';
import FlowStart from '../FlowStart.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';

const { permissions } = vi.hoisted(() => ({ permissions: { admin: true } }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => permissions.admin }),
}));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: {
    list: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    validate: vi.fn(),
  },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  emits: ['confirm'],
  methods: { open: vi.fn(), close: vi.fn() },
};

const flows = [
  {
    id: 1,
    name: 'Datos del cliente',
    categories: ['LEAD_GENERATION'],
    screens: 2,
    updated_at: 1790000000,
  },
];

const mountPanel = async () => {
  const wrapper = mount(FlowsPanel, {
    global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  return wrapper;
};

describe('FlowsPanel', () => {
  beforeEach(() => {
    permissions.admin = true;
    Object.values(WhatsappFlowsAPI).forEach(fn => fn.mockReset());
    WhatsappFlowsAPI.list.mockResolvedValue({ data: { payload: flows } });
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [], flow_json: {} },
    });
  });

  it('lists the forms with their screens and categories', async () => {
    const wrapper = await mountPanel();

    const rows = wrapper.findAll('[data-testid="flow-row"]');
    expect(rows).toHaveLength(1);
    expect(rows[0].text()).toContain('Datos del cliente');
    expect(rows[0].text()).toContain('WHATSAPP_FLOWS.LIST.SCREENS');
    expect(rows[0].text()).toContain(
      'WHATSAPP_FLOWS.CATEGORIES.LEAD_GENERATION'
    );
  });

  it('says there are no forms yet', async () => {
    WhatsappFlowsAPI.list.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flows-empty"]').exists()).toBe(true);
  });

  it('lets only administrators create, edit and delete', async () => {
    permissions.admin = false;
    const wrapper = await mountPanel();

    expect(wrapper.find('[data-testid="flow-new"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="flow-edit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="flow-delete"]').exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="flow-row"]')).toHaveLength(1);
  });

  it('starts a form from the start screen: needs a name, then opens the builder', async () => {
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-new"]').trigger('click');
    expect(wrapper.findComponent(FlowStart).exists()).toBe(true);

    await wrapper.get('[data-testid="flow-start-create"]').trigger('click');
    expect(wrapper.find('[data-testid="flow-editor"]').exists()).toBe(false);

    await wrapper
      .get('[data-testid="flow-start-name"] input')
      .setValue('Mi formulario');
    await wrapper.get('[data-testid="flow-starting-survey"]').trigger('click');
    await wrapper.get('[data-testid="flow-start-create"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="flow-editor"]').exists()).toBe(true);
    expect(wrapper.findAll('[data-testid="flow-screen"]')).toHaveLength(2);
    expect(
      wrapper.get('[data-testid="flow-editor-name"] input').element.value
    ).toBe('Mi formulario');
  });

  it('opens a saved form in the builder and goes back to the refreshed list', async () => {
    WhatsappFlowsAPI.show.mockResolvedValue({
      data: {
        ...flows[0],
        definition: {
          schema_version: 1,
          screens: [
            {
              title: 'Uno',
              button: 'Enviar',
              blocks: [{ type: 'heading', text: 'Hola' }],
            },
          ],
        },
      },
    });
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-edit"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="flow-editor"]').exists()).toBe(true);

    await wrapper.get('[data-testid="flow-editor-back"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="flow-editor"]').exists()).toBe(false);
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
  });

  it('deletes a form after asking', async () => {
    WhatsappFlowsAPI.remove.mockResolvedValue({});
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="flow-delete"]').trigger('click');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(WhatsappFlowsAPI.remove).toHaveBeenCalledWith(1);
    expect(WhatsappFlowsAPI.list).toHaveBeenCalledTimes(2);
  });
});
