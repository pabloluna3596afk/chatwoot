import { flushPromises, mount } from '@vue/test-utils';
import TemplateFormDrawer from '../TemplateFormDrawer.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import { PRESETS, presetToForm } from '../presets';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values?.message ? `${key}: ${values.message}` : key),
    te: () => false,
    locale: { value: 'es' },
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { locale: 'es' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({
    value: [
      {
        attribute_key: 'plan',
        attribute_model: 'contact_attribute',
        attribute_display_name: 'Plan',
      },
      {
        attribute_key: 'estado',
        attribute_model: 'conversation_attribute',
        attribute_display_name: 'Estado',
      },
    ],
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
    WhatsappTemplatesAPI.updateTemplate.mockReset();
    WhatsappTemplatesAPI.getTemplate.mockReset();
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

  it('keeps the language of a duplicated template instead of the account default', async () => {
    WhatsappTemplatesAPI.createTemplate.mockResolvedValue({
      data: { id: 'copy' },
    });
    const wrapper = await mountDrawer();
    const prefill = presetToForm(PRESETS[0]);
    prefill.name = 'template_copia';
    prefill.language = 'en';
    await wrapper.vm.open(null, prefill);
    await flushPromises();
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappTemplatesAPI.createTemplate).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ name: 'template_copia', language: 'en' })
    );
    wrapper.unmount();
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

  it('offers the CRM names, the contact and conversation attributes and the Captain names, grouped', async () => {
    const wrapper = await mountDrawer();

    await wrapper.get('[data-testid="variable-menu-toggle"]').trigger('click');

    const text = wrapper.text();
    [
      'WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.SYSTEM',
      'WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.CONTACT',
      'WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.CONVERSATION',
      'WHATSAPP_TEMPLATE_MGMT.FORM.VARIABLE_GROUPS.CAPTAIN',
      '(nombre)',
      '(correo)',
      '(empresa)',
      'Plan (plan)',
      'Estado (conversacion_estado)',
      'cita',
    ].forEach(expected => expect(text).toContain(expected));
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
  const positional = {
    id: '555',
    name: 'test_utility_envio',
    language: 'es_EC',
    category: 'UTILITY',
    status: 'APPROVED',
    parameter_format: 'POSITIONAL',
    last_updated_time: '2026-10-07T10:00:00Z',
    inboxes,
    components: [
      {
        type: 'BODY',
        text: 'Hola {{1}}, tu pedido #{{2}} llega el {{3}} con el agente {{4}}.',
        example: { body_text: [['Ana', '123', 'lunes', 'Luis']] },
      },
      {
        type: 'BUTTONS',
        buttons: [
          {
            type: 'URL',
            text: 'Seguir',
            url: 'https://paluhub.com/track/{{2}}',
            example: ['https://paluhub.com/track/123'],
          },
        ],
      },
    ],
  };

  it('loads live positional structure, keeps all examples and locks absent components and format', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    WhatsappTemplatesAPI.updateTemplate.mockResolvedValue({ data: {} });
    const wrapper = await mountDrawer();
    await wrapper.vm.open({
      ...positional,
      components: [{ type: 'BODY', text: 'Stale cache' }],
    });
    expect(wrapper.get('textarea').element.value).toBe(
      positional.components[0].text
    );
    expect(wrapper.find('[data-testid="mode-named"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="template-header-format"]').exists()
    ).toBe(false);
    expect(
      wrapper
        .find(
          'input[placeholder="WHATSAPP_TEMPLATE_MGMT.FORM.FOOTER_PLACEHOLDER"]'
        )
        .exists()
    ).toBe(false);
    expect(wrapper.find('[data-testid="approved-warning"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="meta-rules"]').exists()).toBe(false);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappTemplatesAPI.updateTemplate).toHaveBeenCalledWith(
      7,
      '555',
      expect.objectContaining({
        parameter_format: 'POSITIONAL',
        header: expect.objectContaining({ format: 'NONE' }),
        body: {
          text: positional.components[0].text,
          examples: ['Ana', '123', 'lunes', 'Luis'],
        },
        buttons: [
          expect.objectContaining({ url: 'https://paluhub.com/track/{{2}}' }),
        ],
      })
    );
    wrapper.unmount();
  });

  it('uses neutral borders for valid fields and error borders only after failed validation', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    expect(
      wrapper.get('textarea').element.parentElement.className
    ).not.toContain('border-n-ruby');
    expect(
      wrapper
        .findAll('input')
        .some(input => input.classes().includes('outline-n-ruby-8'))
    ).toBe(false);
    await wrapper.get('textarea').setValue('');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.get('textarea').element.parentElement.className).toContain(
      'border-n-ruby'
    );
    wrapper.unmount();
  });

  it('keeps an existing media header visible and retains its example while its format is locked', async () => {
    const source = {
      ...positional,
      components: [
        {
          type: 'HEADER',
          format: 'IMAGE',
          example: { header_handle: ['existing-media-handle'] },
        },
        ...positional.components,
      ],
    };
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: source });
    WhatsappTemplatesAPI.updateTemplate.mockResolvedValue({ data: {} });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(source);
    const header = wrapper
      .findAllComponents(ComboBox)
      .find(
        combo => combo.attributes('data-testid') === 'template-header-format'
      );
    expect(header.props('modelValue')).toBe('IMAGE');
    expect(header.props('options')).toContainEqual(
      expect.objectContaining({ value: 'IMAGE' })
    );
    expect(header.props('disabled')).toBe(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappTemplatesAPI.updateTemplate).toHaveBeenCalledWith(
      7,
      '555',
      expect.objectContaining({
        header: expect.objectContaining({
          format: 'IMAGE',
          handle: 'existing-media-handle',
        }),
      })
    );
    wrapper.unmount();
  });

  it.each([
    'Hola {{1}}, pedido {{2}} con el agente {{4}}.',
    'Hola {{1}}, pedido {{2}}, fecha {{3}}, agente {{4}}, dato {{5}}.',
    'Hola {{1}}, pedido {{3}}, fecha {{2}}, agente {{4}}.',
    'Hola {{nombre}}, pedido {{2}}, fecha {{3}}, agente {{4}}.',
  ])(
    'blocks a changed parameter sequence with a clear message: %s',
    async text => {
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
      const wrapper = await mountDrawer();
      await wrapper.vm.open(positional);
      await wrapper.get('textarea').setValue(text);
      await wrapper.get('form').trigger('submit');
      expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
      expect(wrapper.text()).toContain(
        'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.EDIT_STRUCTURE_LOCKED'
      );
      wrapper.unmount();
    }
  );

  it('creates a named copy only after each system mapping is chosen and the user submits', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    WhatsappTemplatesAPI.createTemplate.mockResolvedValue({
      data: { id: 'copy' },
    });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    await wrapper.get('[data-testid="system-copy-open"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('input[type="text"]').element.value).toBe(
      'test_utility_envio_v2'
    );
    await wrapper.get('form').trigger('submit');
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.SYSTEM_MAPPING_REQUIRED'
    );
    const choices = {
      1: 'nombre',
      2: 'numero_conversacion',
      3: 'ciudad',
      4: 'agente',
    };
    Object.entries(choices).forEach(([token, name]) => {
      wrapper
        .findAllComponents(ComboBox)
        .find(
          combo => combo.attributes('data-testid') === `map-variable-${token}`
        )
        .vm.$emit('update:modelValue', name);
    });
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappTemplatesAPI.createTemplate).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        name: 'test_utility_envio_v2',
        parameter_format: 'NAMED',
        body: {
          text: 'Hola {{nombre}}, tu pedido #{{numero_conversacion}} llega el {{ciudad}} con el agente {{agente}}.',
          examples: ['Ana', '123', 'lunes', 'Luis'],
        },
        buttons: [
          expect.objectContaining({
            url: 'https://paluhub.com/track/{{numero_conversacion}}',
          }),
        ],
      })
    );
    expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows both Meta messages in the drawer after a rejected edit', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    WhatsappTemplatesAPI.updateTemplate.mockRejectedValue({
      response: {
        data: {
          message: 'Invalid parameter',
          error_user_msg: 'Solo una edición cada 24 horas',
          code: 100,
          error_subcode: 123,
        },
      },
    });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    // The translated framing receives the original text as interpolation.
    expect(wrapper.get('[data-testid="meta-error"]').text()).toContain(
      'Solo una edición cada 24 horas — Invalid parameter'
    );
    expect(wrapper.emitted('saved')).toBeUndefined();
    wrapper.unmount();
  });
});
