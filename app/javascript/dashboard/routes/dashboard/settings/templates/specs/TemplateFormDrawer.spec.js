import { flushPromises, mount } from '@vue/test-utils';
import TemplateFormDrawer from '../TemplateFormDrawer.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
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
});
