import { flushPromises, mount } from '@vue/test-utils';
import TemplateFormDrawer from '../TemplateFormDrawer.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import { PRESETS, presetToForm } from '../presets';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { CAPTAIN_VARIABLES } from '../templateForm';

const userLocale = vi.hoisted(() => ({ value: 'es' }));
const currentRole = vi.hoisted(() => ({ value: 'administrator' }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values?.message ? `${key}: ${values.message}` : key),
    te: () => false,
    locale: userLocale,
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { locale: 'es' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  const attributes = ref([
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
  ]);
  const store = { dispatch: vi.fn() };
  return {
    useStore: () => store,
    useMapGetter: key => (key === 'getCurrentRole' ? currentRole : attributes),
  };
});
vi.mock(
  'dashboard/routes/dashboard/settings/attributes/AddAttribute.vue',
  () => ({
    __esModule: true,
    default: {
      name: 'AddAttribute',
      props: ['onClose', 'selectedAttributeModelTab'],
      template: '<div data-testid="add-attribute" />',
    },
  })
);
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

const mountDrawer = async (props = {}, realPanel = false) => {
  const wrapper = mount(TemplateFormDrawer, {
    props: { inboxes, ...props },
    attachTo: realPanel ? document.body : undefined,
    global: {
      mocks: {
        $t: (key, values) => (values?.time ? `${key}: ${values.time}` : key),
      },
      stubs: {
        ...(realPanel ? {} : { SidePanel: SidePanelStub, Teleport: true }),
        TemplatePreview: true,
      },
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
    userLocale.value = 'es';
    currentRole.value = 'administrator';
    useMapGetter('attributes/getAttributes').value = [
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
    ];
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

    const picker = wrapper.findComponent(
      '[data-testid="variable-menu-toggle"]'
    );
    await picker.get('button').trigger('click');

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
    await picker
      .findAll('[role="option"]')
      .find(option => option.text() === 'Plan (plan)')
      .trigger('click');
    expect(wrapper.get('textarea').element.value).toContain('{{plan}}');
    expect(
      picker.props('options').some(option => option.value === 'plan')
    ).toBe(false);
    wrapper.unmount();
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

  it.each(['new', 'edit', 'copy'])(
    'keeps every %s picker fixed outside the drawer scroll container',
    async mode => {
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
      const wrapper = await mountDrawer(
        { inboxes: [...inboxes, { id: 8, name: 'Ventas' }] },
        true
      );
      if (mode !== 'new') await wrapper.vm.open(positional);
      if (mode === 'copy') await wrapper.vm.openSystemCopy(positional);
      await flushPromises();
      const selectors = ['template-inbox', 'template-language'];
      if (mode !== 'edit') selectors.push('template-header-format');
      if (mode === 'new') selectors.push('variable-menu-toggle');
      if (mode === 'copy')
        selectors.push(
          ...['1', '2', '3', '4'].map(token => `map-variable-${token}`)
        );
      selectors.forEach(testId => {
        const selector = wrapper.findComponent(`[data-testid="${testId}"]`);
        expect(selector.props('teleport')).toBe(true);
        expect(selector.props('placeholder')).toBeTruthy();
        expect(selector.get('button').classes()).toContain('!py-2.5');
        expect(selector.get('button').classes()).toContain('font-normal');
      });
      const scrollContainer = document.querySelector(
        'aside > .overflow-y-auto'
      );
      expect(scrollContainer).not.toBeNull();
      expect(
        scrollContainer.querySelector('[data-combobox-dropdown]')
      ).toBeNull();
      const menus = selectors.map(
        testId =>
          wrapper
            .findComponent(`[data-testid="${testId}"]`)
            .findComponent(ComboBoxDropdown).element
      );
      expect(menus).toHaveLength(selectors.length);
      menus.forEach(menu => {
        expect(menu.parentElement).toBe(document.body);
        // Fixed positioning excludes the list from the document's layout flow.
        expect(menu.style.position).toBe('fixed');
      });
      expect(
        document.querySelector('[data-template-picker-portal]')
      ).toBeNull();
      expect(wrapper.find('select').exists()).toBe(false);
      selectors.forEach(testId => {
        expect(
          wrapper
            .findComponent(`[data-testid="${testId}"]`)
            .findComponent(ComboBoxDropdown)
            .findComponent({ name: 'DropdownMenu' })
            .exists()
        ).toBe(true);
      });
      wrapper.unmount();
    }
  );

  it.each(['es', 'en', 'pt_BR'])(
    'formats the last edit in the user locale %s and local timezone',
    async locale => {
      userLocale.value = locale;
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
      const wrapper = await mountDrawer();
      await wrapper.vm.open(positional);
      const expected = new Intl.DateTimeFormat(locale.replace('_', '-'), {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      }).format(new Date(positional.last_updated_time));
      expect(wrapper.text()).toContain(
        `WHATSAPP_TEMPLATE_MGMT.FORM.LAST_EDIT: ${expected}`
      );
      expect(wrapper.text()).not.toContain(positional.last_updated_time);
      wrapper.unmount();
    }
  );

  it.each([undefined, null, '', 'invalid-date'])(
    'hides the last edit when the timestamp is %s',
    async timestamp => {
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({
        data: { ...positional, last_updated_time: timestamp },
      });
      const wrapper = await mountDrawer();
      await wrapper.vm.open(positional);
      expect(wrapper.text()).not.toContain(
        'WHATSAPP_TEMPLATE_MGMT.FORM.LAST_EDIT'
      );
      expect(wrapper.text()).not.toContain('Invalid Date');
      wrapper.unmount();
    }
  );

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

  it('offers the same grouped variables as the editor, including attributes and Captain', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    await wrapper.get('[data-testid="system-copy-open"]').trigger('click');
    await flushPromises();
    const select = wrapper.findComponent('[data-testid="map-variable-1"]');
    expect(select.props('groups')).toEqual(
      ['system', 'contact', 'conversation', 'appointment'].map(key => ({
        key,
        label: `VARIABLE_PICKER.GROUPS.${key.toUpperCase()}`,
        emptyState: 'VARIABLE_PICKER.NO_COMPATIBLE',
      }))
    );
    expect(select.props('options')).toEqual(
      expect.arrayContaining([
        { value: 'plan', label: 'Plan (plan)', group: 'contact' },
        {
          value: 'conversacion_estado',
          label: 'Estado (conversacion_estado)',
          group: 'conversation',
        },
        ...CAPTAIN_VARIABLES.map(name => ({
          value: name,
          label: `VARIABLE_PICKER.LABELS.${name} (${name})`,
          group: 'appointment',
        })),
      ])
    );
    await select.get('button').trigger('click');
    expect(select.get('input[type="search"]').attributes('placeholder')).toBe(
      'VARIABLE_PICKER.SEARCH'
    );
    await select.get('input[type="search"]').setValue('Plan');
    expect(
      select.findAll('[role="option"]').map(option => option.text())
    ).toEqual(['Plan (plan)']);
    await select.get('[role="option"]').trigger('click');
    // Chosen variables remain available for the other tokens (duplicates are validated on save).
    expect(select.props('options')).toContainEqual({
      value: 'plan',
      label: 'Plan (plan)',
      group: 'contact',
    });
    wrapper.unmount();
  });

  it('reuses the attribute modal and refreshes options when it closes', async () => {
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    await wrapper.get('[data-testid="system-copy-open"]').trigger('click');
    await flushPromises();
    const select = wrapper.findComponent('[data-testid="map-variable-1"]');
    await select.get('button').trigger('click');
    await select
      .get('[data-testid="variable-create-attribute"]')
      .trigger('click');
    await flushPromises();
    const modal = wrapper.findComponent({ name: 'AddAttribute' });
    expect(modal.props('selectedAttributeModelTab')).toBe(1);
    expect(select.get('button').attributes('aria-expanded')).toBe('false');
    useStore().dispatch.mockImplementationOnce(async () => {
      useMapGetter('attributes/getAttributes').value.push({
        attribute_key: 'nuevo',
        attribute_model: 'conversation_attribute',
        attribute_display_name: 'Nuevo',
      });
    });
    await modal.props('onClose')();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AddAttribute' }).exists()).toBe(
      false
    );
    expect(useStore().dispatch).toHaveBeenLastCalledWith('attributes/get');
    expect(select.props('options')).toContainEqual({
      value: 'conversacion_nuevo',
      label: 'Nuevo (conversacion_nuevo)',
      group: 'conversation',
    });
    wrapper.unmount();
  });

  it('hides the create-attribute CTA for agents', async () => {
    currentRole.value = 'agent';
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    const wrapper = await mountDrawer();
    await wrapper.vm.open(positional);
    await wrapper.get('[data-testid="system-copy-open"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="variable-create-attribute"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('creates a named copy only after each mapping is chosen and the user submits', async () => {
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
      2: 'plan',
      3: 'conversacion_estado',
      4: 'cita',
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
          text: 'Hola {{nombre}}, tu pedido #{{plan}} llega el {{conversacion_estado}} con el agente {{cita}}.',
          examples: ['Ana', '123', 'lunes', 'Luis'],
        },
        buttons: [
          expect.objectContaining({
            url: 'https://paluhub.com/track/{{plan}}',
          }),
        ],
      })
    );
    expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each(['nombre', 'not_an_available_variable'])(
    'blocks duplicate or unavailable copy mappings: %s',
    async second => {
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
      const wrapper = await mountDrawer();
      await wrapper.vm.open(positional);
      await wrapper.get('[data-testid="system-copy-open"]').trigger('click');
      await flushPromises();
      Object.entries({ 1: 'nombre', 2: second, 3: 'plan', 4: 'cita' }).forEach(
        ([token, name]) => {
          wrapper
            .findComponent(`[data-testid="map-variable-${token}"]`)
            .vm.$emit('update:modelValue', name);
        }
      );
      await wrapper.get('form').trigger('submit');
      expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
      expect(wrapper.text()).toContain(
        'WHATSAPP_TEMPLATE_MGMT.FORM.ERRORS.SYSTEM_MAPPING_REQUIRED'
      );
      wrapper.unmount();
    }
  );

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
