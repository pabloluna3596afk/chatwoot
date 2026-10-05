import { flushPromises, mount } from '@vue/test-utils';
import FlowEditor from '../FlowEditor.vue';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import { startingDefinition } from '../flowDefinition';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappFlows', () => ({
  default: {
    validate: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
  },
}));

const mountEditor = (flow = {}) =>
  mount(FlowEditor, {
    props: {
      flow: {
        id: null,
        name: 'Soporte',
        categories: ['CUSTOMER_SUPPORT'],
        definition: startingDefinition('support'),
        ...flow,
      },
    },
    global: { mocks: { $t: key => key } },
  });

describe('FlowEditor', () => {
  beforeEach(() => {
    WhatsappFlowsAPI.validate.mockReset();
    WhatsappFlowsAPI.create.mockReset();
    WhatsappFlowsAPI.update.mockReset();
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [], flow_json: { version: '7.3' } },
    });
  });

  it('shows the screens and blocks of the form and checks it on open', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    expect(wrapper.findAll('[data-testid="flow-screen"]')).toHaveLength(1);
    expect(wrapper.findAll('[data-testid="flow-block"]')).toHaveLength(6);
    expect(WhatsappFlowsAPI.validate).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-testid="flow-editor-state"]').text()).toBe(
      'WHATSAPP_FLOWS.EDITOR.READY'
    );
    expect(wrapper.find('[data-testid="flow-preview"]').exists()).toBe(true);
  });

  it('shows where the mistakes are and says how many there are', async () => {
    WhatsappFlowsAPI.validate.mockResolvedValue({
      data: {
        valid: false,
        errors: [
          {
            code: 'screen_title_required',
            path: 'screens.0.title',
            details: {},
          },
          {
            code: 'label_required',
            path: 'screens.0.blocks.1.label',
            details: {},
          },
        ],
        flow_json: null,
      },
    });
    const wrapper = mountEditor();
    await flushPromises();

    expect(wrapper.get('[data-testid="flow-editor-state"]').text()).toBe(
      'WHATSAPP_FLOWS.EDITOR.TO_FIX'
    );
    expect(wrapper.text()).toContain('screen_title_required');
    expect(wrapper.text()).toContain('label_required');
  });

  it('adds and removes screens, but keeps one', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper.get('[data-testid="flow-screen-add"]').trigger('click');
    expect(wrapper.findAll('[data-testid="flow-screen"]')).toHaveLength(2);

    await wrapper
      .findAll('[data-testid="flow-screen-remove"]')[1]
      .trigger('click');
    expect(wrapper.findAll('[data-testid="flow-screen"]')).toHaveLength(1);
    expect(
      wrapper.get('[data-testid="flow-screen-remove"]').attributes('disabled')
    ).toBeDefined();
  });

  it('removes a block', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper
      .findAll('[data-testid="flow-block-remove"]')[0]
      .trigger('click');

    expect(wrapper.findAll('[data-testid="flow-block"]')).toHaveLength(5);
  });

  it('saves a new form with its name, categories and definition, then updates it', async () => {
    WhatsappFlowsAPI.create.mockResolvedValue({
      data: { id: 9, name: 'Soporte' },
    });
    WhatsappFlowsAPI.update.mockResolvedValue({
      data: { id: 9, name: 'Soporte 2' },
    });
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();

    const [payload] = WhatsappFlowsAPI.create.mock.calls[0];
    expect(payload).toMatchObject({
      name: 'Soporte',
      categories: ['CUSTOMER_SUPPORT'],
    });
    expect(payload.definition.screens).toHaveLength(1);
    expect(wrapper.emitted('saved')[0][0]).toMatchObject({ id: 9 });

    await wrapper
      .get('[data-testid="flow-editor-name"] input')
      .setValue('Soporte 2');
    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');
    await flushPromises();

    expect(WhatsappFlowsAPI.update).toHaveBeenCalledWith(
      9,
      expect.objectContaining({ name: 'Soporte 2' })
    );
  });

  it('does not save without a name', async () => {
    const wrapper = mountEditor({ name: '' });
    await flushPromises();

    await wrapper.get('[data-testid="flow-editor-save"]').trigger('click');

    expect(WhatsappFlowsAPI.create).not.toHaveBeenCalled();
  });

  it('shows the JSON Meta will get once the form is valid', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper.get('[data-testid="flow-json-toggle"]').trigger('click');

    expect(wrapper.get('[data-testid="flow-json"]').text()).toContain('7.3');
  });

  it('goes back', async () => {
    const wrapper = mountEditor();
    await flushPromises();

    await wrapper.get('[data-testid="flow-editor-back"]').trigger('click');

    expect(wrapper.emitted('back')).toHaveLength(1);
  });
});
