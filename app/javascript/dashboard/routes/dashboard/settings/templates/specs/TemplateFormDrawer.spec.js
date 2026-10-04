import { flushPromises, mount } from '@vue/test-utils';
import TemplateFormDrawer from '../TemplateFormDrawer.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import { PRESETS, presetToForm } from '../presets';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false, locale: { value: 'es' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { locale: 'es' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({
    value: () => [{ attribute_key: 'plan', attribute_display_name: 'Plan' }],
  }),
}));
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: {
    capabilities: vi.fn(),
    getTemplate: vi.fn(),
    createTemplate: vi.fn(),
    updateTemplate: vi.fn(),
    uploadHeaderExample: vi.fn(),
  },
}));

const inboxes = [{ id: 7, name: 'Soporte' }];

const SidePanelStub = {
  template: '<div><slot /><slot name="footer" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};

const mountDrawer = async (props = {}) => {
  const wrapper = mount(TemplateFormDrawer, {
    props: { inboxes, ...props },
    global: {
      mocks: { $t: key => key },
      stubs: { SidePanel: SidePanelStub, TemplatePreview: true },
    },
  });
  await wrapper.vm.open();
  await flushPromises();
  return wrapper;
};

const typeInto = async (wrapper, selector, value) => {
  const input = wrapper.get(selector);
  await input.setValue(value);
};

describe('TemplateFormDrawer', () => {
  beforeEach(() => {
    WhatsappTemplatesAPI.capabilities.mockReset();
    WhatsappTemplatesAPI.createTemplate.mockReset();
    WhatsappTemplatesAPI.capabilities.mockResolvedValue({
      data: { media_header: false },
    });
  });

  it('shows the Meta rules and says why media headers are missing when the channel cannot upload examples', async () => {
    const wrapper = await mountDrawer();

    expect(wrapper.find('[data-testid="meta-rules"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="media-header-unavailable"]').exists()
    ).toBe(true);
  });

  it('does not call Meta while the form has mistakes', async () => {
    const wrapper = await mountDrawer();

    await wrapper.get('form').trigger('submit');

    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.NAME_INVALID'
    );
    expect(wrapper.text()).toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.BODY_REQUIRED'
    );
  });

  it('creates the template with the snake_case name and the body typed', async () => {
    WhatsappTemplatesAPI.createTemplate.mockResolvedValue({
      data: { id: '9' },
    });
    const wrapper = await mountDrawer();

    await typeInto(wrapper, 'input[type="text"]', 'Recordatorio de cita');
    await typeInto(wrapper, 'textarea', 'Tu cita queda confirmada.');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(WhatsappTemplatesAPI.createTemplate).toHaveBeenCalledTimes(1);
    const [inboxId, payload] =
      WhatsappTemplatesAPI.createTemplate.mock.calls[0];
    expect(inboxId).toBe(7);
    expect(payload).toMatchObject({
      name: 'recordatorio_de_cita',
      language: 'es',
      category: 'UTILITY',
      body: { text: 'Tu cita queda confirmada.' },
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('opens filled in with a preset and creates it with named variables', async () => {
    WhatsappTemplatesAPI.createTemplate.mockResolvedValue({
      data: { id: '9' },
    });
    const wrapper = mount(TemplateFormDrawer, {
      props: { inboxes },
      global: {
        mocks: { $t: key => key },
        stubs: { SidePanel: SidePanelStub, TemplatePreview: true },
      },
    });
    await wrapper.vm.open(null, presetToForm(PRESETS[0]));
    await flushPromises();

    expect(wrapper.get('input[type="text"]').element.value).toBe(
      'recordatorio_cita'
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    const [inboxId, payload] =
      WhatsappTemplatesAPI.createTemplate.mock.calls[0];
    expect(inboxId).toBe(7);
    expect(payload.body.text).toContain('{{nombre}}');
    expect(payload.body.examples).toEqual([
      'Ana',
      'Consulta',
      'jueves 8 de octubre',
      '10:30',
    ]);
    expect(payload.category).toBe('UTILITY');
  });

  it('adds a custom named variable to the body at the cursor and asks for its example', async () => {
    const wrapper = await mountDrawer();

    await typeInto(wrapper, 'textarea', 'Hola ');
    await typeInto(
      wrapper,
      'input[placeholder="WHATSAPP_TEMPLATE_MGMT.FORM.CUSTOM_VARIABLE"]',
      'nombre'
    );
    const add = wrapper
      .findAll('button')
      .find(button => button.text() === 'WHATSAPP_TEMPLATE_MGMT.FORM.ADD');
    await add.trigger('click');

    expect(wrapper.get('textarea').element.value).toBe('Hola {{nombre}}');
    expect(wrapper.find('[data-testid="examples"]').exists()).toBe(true);
  });

  it('offers the contact attributes and the names Captain fills in in the variable menu', async () => {
    const wrapper = await mountDrawer();

    await wrapper.get('[data-testid="variable-menu-toggle"]').trigger('click');

    expect(wrapper.text()).toContain('nombre');
    expect(wrapper.text()).toContain('Plan (plan)');
  });

  it('warns when a Utility template reads as promotional, and not for Marketing', async () => {
    const wrapper = await mountDrawer();

    await typeInto(wrapper, 'textarea', 'Aprovecha el descuento de hoy');
    expect(wrapper.find('[data-testid="promo-warning"]').exists()).toBe(true);

    await wrapper.get('input[type="radio"][value="MARKETING"]').setValue(true);
    expect(wrapper.find('[data-testid="promo-warning"]').exists()).toBe(false);
  });

  it('says when Meta classified the template in another category', async () => {
    WhatsappTemplatesAPI.createTemplate.mockResolvedValue({
      data: { id: '9', category: 'MARKETING' },
    });
    const wrapper = await mountDrawer();

    await typeInto(wrapper, 'input[type="text"]', 'prueba');
    await typeInto(wrapper, 'textarea', 'Tu cita queda confirmada.');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORY_CHANGED'
    );
  });

  it('says why media headers are missing when the channel gave a reason', async () => {
    WhatsappTemplatesAPI.capabilities.mockResolvedValue({
      data: { media_header: false, reason: 'upload_refused' },
    });
    const wrapper = await mountDrawer();

    expect(
      wrapper.get('[data-testid="media-header-unavailable"]').text()
    ).toContain('WHATSAPP_TEMPLATE_MGMT.FORM');
  });
});
