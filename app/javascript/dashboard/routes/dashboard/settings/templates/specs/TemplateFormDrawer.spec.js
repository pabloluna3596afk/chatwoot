import { flushPromises, mount } from '@vue/test-utils';
import { mockNativeDialog } from 'dashboard/helper/specs/mockNativeDialog';
import TemplateFormDrawer from '../TemplateFormDrawer.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import { PRESETS, presetToForm } from '../presets';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ComboBoxDropdown from 'dashboard/components-next/combobox/ComboBoxDropdown.vue';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { draftFromForm } from '../templateDrafts';
import { emptyForm } from '../templateForm';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';
vi.mock('dashboard/api/inboxes', () => ({
  default: { updateWhatsappTemplateVariableBindings: vi.fn(async () => ({})) },
}));
import VariablesAPI from 'dashboard/api/variables';
import catalog from 'dashboard/components-next/variable-picker/specs/catalog.json';
vi.mock('dashboard/api/variables', () => ({ default: { catalog: vi.fn() } }));

const userLocale = vi.hoisted(() => ({ value: 'es' }));
const currentRole = vi.hoisted(() => ({ value: 'administrator' }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values?.message ? `${key}: ${values.message}` : key),
    te: key => key.startsWith('VARIABLE_PICKER.LABELS.'),
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
    useMapGetter: key => {
      if (key === 'getCurrentAccountId') return { value: 1 };
      return key === 'getCurrentRole' ? currentRole : attributes;
    },
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
vi.mock('dashboard/api/whatsappTemplateDrafts', () => ({
  default: Object.fromEntries(
    [
      'create',
      'update',
      'show',
      'submit',
      'uploadMedia',
      'removeMedia',
      'downloadMedia',
      'newVersion',
      'duplicate',
      'reconcile',
    ].map(key => [key, vi.fn()])
  ),
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

const inboxes = [
  {
    id: 7,
    channel_id: 70,
    name: 'Soporte',
    provider: 'whatsapp_cloud',
    provider_config: { business_account_id: 'waba-a' },
  },
];

const SidePanelStub = {
  template: '<div><slot name="header" /><slot /><slot name="footer" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};

beforeEach(mockNativeDialog);

const mountDrawer = async (props = {}, realPanel = false) => {
  const wrapper = mount(TemplateFormDrawer, {
    props: { inboxes, ...props },
    attachTo: realPanel ? document.body : undefined,
    global: {
      mocks: {
        $te: () => true,
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

describe('TemplateFormDrawer drafts', () => {
  const record = {
    id: 31,
    lock_version: 2,
    status: 'draft',
    submissions: [],
    media: null,
    ...draftFromForm(
      {
        ...emptyForm(),
        inboxId: 7,
        name: 'appointment',
        body: { text: 'Your appointment is confirmed.', examples: [] },
      },
      inboxes
    ),
  };
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
        text: 'Hola {{1}}, tu pedido está confirmado.',
        example: { body_text: [['Ana']] },
      },
    ],
  };
  beforeEach(() => {
    VariablesAPI.catalog.mockResolvedValue({ data: structuredClone(catalog) });
    userLocale.value = 'es';
    currentRole.value = 'administrator';
    DraftsAPI.create.mockImplementation(async attrs => ({
      data: { ...record, ...attrs, lock_version: 0 },
    }));
    DraftsAPI.update.mockImplementation(async (id, attrs) => ({
      data: { ...record, ...attrs, id, lock_version: attrs.lock_version + 1 },
    }));
    DraftsAPI.show.mockResolvedValue({ data: structuredClone(record) });
    DraftsAPI.submit.mockResolvedValue({
      data: { id: 99, revision: 2, status: 'submitting' },
    });
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
    URL.createObjectURL = vi.fn(() => 'blob:local-preview');
    URL.revokeObjectURL = vi.fn();
  });
  afterEach(() => {
    document.body.innerHTML = '';
  });
  it('shows the correct title for a new template, an edited draft and a new version', async () => {
    const wrapper = await mountDrawer();
    expect(wrapper.get('h3').text()).toBe(
      'WHATSAPP_TEMPLATE_MGMT.FORM.NEW_TITLE'
    );

    await wrapper.vm.open(positional);
    expect(wrapper.get('h3').text()).toBe(positional.name);

    await wrapper.vm.openDraft(record);
    expect(wrapper.get('h3').text()).toBe(
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.EDIT_TITLE'
    );

    DraftsAPI.show.mockResolvedValueOnce({
      data: { ...record, source_remote_id: 'meta-template-1' },
    });
    await wrapper.vm.openDraft(record);
    expect(wrapper.get('h3').text()).toBe(
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.NEW_VERSION_TITLE'
    );
    wrapper.unmount();
  });

  it('keeps every footer action label visible in full on mobile', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    const footer = wrapper
      .findAll('div')
      .find(element => element.classes().includes('grid-cols-1'));
    expect(footer.classes()).toContain('sm:flex');
    expect(footer.get('[data-testid="submit-draft"]').classes()).toContain(
      'w-full'
    );
    expect(footer.get('[data-testid="submit-draft"]').classes()).toContain(
      'sm:order-last'
    );
    ['save-draft', 'template-preview-open'].forEach(testId => {
      const button = footer.get(`[data-testid="${testId}"]`);
      expect(button.classes()).toContain('w-full');
    });
    ['submit-draft', 'save-draft', 'template-preview-open'].forEach(testId => {
      const button = footer.get(`[data-testid="${testId}"]`);
      expect(button.text()).not.toBe('');
    });
    footer.findAll('button').forEach(button => {
      expect(button.html()).not.toMatch(
        /\b(truncate|text-ellipsis|line-clamp(?:-\d+)?)\b/
      );
    });
    expect(footer.get('button:not([data-testid])').classes()).toContain(
      'justify-self-end'
    );
    expect(
      footer
        .findAll('button')
        .map(button => button.attributes('data-testid') || button.text())
    ).toEqual([
      'submit-draft',
      'save-draft',
      'template-preview-open',
      'WHATSAPP_TEMPLATE_MGMT.FORM.CANCEL',
    ]);
    wrapper.unmount();
  });
  it('hides the generated-name hint when it matches the entered name', async () => {
    const wrapper = await mountDrawer();
    const name = wrapper.get(
      'input[placeholder="WHATSAPP_TEMPLATE_MGMT.FORM.NAME_PLACEHOLDER"]'
    );
    await name.setValue('welcome_message');
    expect(wrapper.text()).not.toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.NAME_SAVED_AS'
    );
    await name.setValue('Welcome Message');
    expect(wrapper.text()).toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.NAME_SAVED_AS'
    );
    wrapper.unmount();
  });
  it('keeps explanations in tooltips, lets the body grow and puts Agregar variable by the counter', async () => {
    const wrapper = await mountDrawer();

    // The long description and each category help are info icons now, not repeated paragraphs.
    expect(wrapper.find('[data-testid="form-info"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="category-info-UTILITY"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).not.toContain(
      'WHATSAPP_TEMPLATE_MGMT.FORM.CATEGORIES.UTILITY.HELP'
    );
    // The body is user-resizable and the variable button sits inside the same relative box as the counter.
    const body = wrapper.findComponent({ name: 'TextArea' });
    expect(body.props('resize')).toBe(true);
    const picker = wrapper.get('[data-testid="variable-picker"]');
    expect(picker.classes()).toContain('absolute');
    expect(picker.element.parentElement.contains(body.element)).toBe(true);
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

  it('offers the CRM names, the contact and conversation attributes from the server, excluding unavailable Captain contexts', async () => {
    const wrapper = await mountDrawer();

    const picker = wrapper.findComponent(
      '[data-testid="variable-menu-toggle"]'
    );
    await picker.get('button').trigger('click');

    const text = wrapper.text();
    [
      'VARIABLE_PICKER.GROUPS.SYSTEM',
      'VARIABLE_PICKER.GROUPS.CONTACT',
      'VARIABLE_PICKER.GROUPS.CONVERSATION',
      '(nombre)',
      '(correo)',
      '(empresa)',
      'Plan (plan)',
      'Estado (conversacion_estado)',
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

  it('numbered variables add the next {{n}} with one button, no list to choose from', async () => {
    const wrapper = await mountDrawer();
    await wrapper.get('[data-testid="mode-positional"]').trigger('click');
    const add = wrapper.get('[data-testid="variable-menu-toggle"]');
    expect(add.text()).toBe('{{1}}');
    await add.trigger('click');
    expect(wrapper.get('textarea').element.value).toContain('{{1}}');
    expect(wrapper.get('[data-testid="variable-menu-toggle"]').text()).toBe(
      '{{2}}'
    );
    wrapper.unmount();
  });

  it('warns when a Utility template reads as promotional, and not for Marketing', async () => {
    const wrapper = await mountDrawer();

    await typeInto(wrapper, 'textarea', 'Aprovecha el descuento de hoy');
    expect(wrapper.find('[data-testid="promo-warning"]').exists()).toBe(true);

    await wrapper.get('input[type="radio"][value="MARKETING"]').setValue(true);
    expect(wrapper.find('[data-testid="promo-warning"]').exists()).toBe(false);
  });

  it('edits synced positional bindings locally even without Meta examples', async () => {
    const template = {
      ...positional,
      components: [{ type: 'BODY', text: 'Hola {{1}} {{nombre}} {{pedido}}' }],
      variable_sources: {
        body: {
          1: { source: 'missing', path: null },
          nombre: { source: 'alias', path: 'contact.name' },
          pedido: { source: 'binding', path: 'contact.email' },
        },
      },
    };
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: template });
    const wrapper = await mountDrawer();
    await wrapper.vm.openBindings(template);
    const section = wrapper.get('[data-testid="variable-values"]');
    expect(section.text()).toContain('VARIABLE_AUTOMATIC');
    const pickers = section.findAllComponents(VariablePicker);
    expect(pickers[0].props('modelValue')).toBe('');
    pickers[0].vm.$emit('update:modelValue', 'contact.name');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
    expect(
      InboxesAPI.updateWhatsappTemplateVariableBindings
    ).toHaveBeenCalledWith(7, {
      name: template.name,
      variable_bindings: { 1: 'contact.name', pedido: 'contact.email' },
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
    wrapper.unmount();
  });

  it.each(['unsupported content', 'Meta unavailable', '360dialog'])(
    'keeps local bindings editable with %s',
    async reason => {
      const template = {
        ...positional,
        components: [
          { type: 'BODY', text: 'Hola {{1}}' },
          ...(reason === 'unsupported content'
            ? [{ type: 'CAROUSEL', cards: [] }]
            : []),
        ],
        variable_sources: { body: { 1: { source: 'missing' } } },
      };
      if (reason === 'Meta unavailable')
        WhatsappTemplatesAPI.getTemplate.mockRejectedValue(
          new Error('offline')
        );
      else
        WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: template });
      const wrapper = await mountDrawer({
        inboxes:
          reason === '360dialog'
            ? [{ ...inboxes[0], provider: 'default' }]
            : inboxes,
      });
      await wrapper.vm.openBindings(template);
      expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
      const picker = wrapper
        .get('[data-testid="variable-values"]')
        .findComponent(VariablePicker);
      picker.vm.$emit('update:modelValue', 'contact.name');
      await flushPromises();
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
      expect(
        InboxesAPI.updateWhatsappTemplateVariableBindings
      ).toHaveBeenCalledWith(7, {
        name: template.name,
        variable_bindings: { 1: 'contact.name' },
      });
      expect(wrapper.emitted('saved')).toHaveLength(1);
      wrapper.unmount();
    }
  );

  it('keeps the editor open when saving local variables fails', async () => {
    const template = {
      ...positional,
      variable_sources: { body: { 1: { source: 'missing' } } },
    };
    WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: template });
    InboxesAPI.updateWhatsappTemplateVariableBindings.mockRejectedValueOnce(
      new Error('offline')
    );
    const wrapper = await mountDrawer();
    await wrapper.vm.openBindings(template);
    wrapper
      .get('[data-testid="variable-values"]')
      .findComponent(VariablePicker)
      .vm.$emit('update:modelValue', 'contact.name');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-testid="meta-error"]').text()).toContain(
      'SAVE_ERROR'
    );
    expect(wrapper.emitted('saved')).toBeUndefined();
    expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each(['new', 'edit'])(
    'keeps every %s picker fixed outside the drawer scroll container',
    async mode => {
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: positional });
      const wrapper = await mountDrawer(
        {
          inboxes: [
            ...inboxes,
            { id: 8, name: 'Ventas', provider: 'whatsapp_cloud' },
          ],
        },
        true
      );
      if (mode !== 'new') await wrapper.vm.open(positional);
      await flushPromises();
      const selectors = ['template-inbox', 'template-language'];
      if (mode !== 'edit') selectors.push('template-header-format');
      if (mode === 'new') selectors.push('variable-menu-toggle');
      selectors.forEach(testId => {
        const selector = wrapper.findComponent(`[data-testid="${testId}"]`);
        expect(selector.props('teleport')).toBe(true);
        expect(selector.props('placeholder')).toBeTruthy();
        expect(selector.get('button').classes()).toContain('!py-2.5');
        expect(selector.get('button').classes()).toContain('font-normal');
      });
      const scrollContainer = document.querySelector(
        'dialog > .overflow-y-auto'
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
        expect(menu.parentElement).toBe(document.querySelector('dialog[open]'));
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

  it('saves an incomplete draft without a channel and never contacts Meta', async () => {
    const wrapper = await mountDrawer({ inboxes: [] });
    expect(wrapper.get('[data-testid="save-draft"]').classes()).toContain(
      'bg-n-brand'
    );
    expect(wrapper.find('[data-testid="submit-draft"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('DRAFTS.NO_DESTINATION_HELP');
    await wrapper
      .get('[data-testid="draft-title"] input')
      .setValue('Work in progress');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        title: 'Work in progress',
        name: null,
        preferred_channel_id: null,
        waba_id: null,
        definition: expect.objectContaining({
          body: { text: '', examples: [] },
        }),
      })
    );
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    expect(DraftsAPI.submit).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVED'
    );
    expect(
      wrapper.get('[data-testid="submit-draft"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('shows submit as primary only after saving a valid draft; save stays local', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    expect(wrapper.get('[data-testid="submit-draft"]').classes()).toContain(
      'bg-n-brand'
    );
    expect(wrapper.get('[data-testid="save-draft"]').classes()).toContain(
      'bg-n-slate-9/10'
    );
    await wrapper.get('textarea').setValue('Changed content.');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.update).toHaveBeenCalledWith(
      31,
      expect.objectContaining({
        lock_version: 2,
        preferred_channel_id: 70,
        waba_id: 'waba-a',
        definition: expect.objectContaining({
          body: { text: 'Changed content.', examples: [] },
        }),
      })
    );
    expect(DraftsAPI.submit).not.toHaveBeenCalled();
    DraftsAPI.show.mockResolvedValue({
      data: {
        ...record,
        lock_version: 3,
        status: 'submitting',
        submissions: [{ id: 99, revision: 3, status: 'submitting' }],
      },
    });
    await wrapper.get('[data-testid="submit-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.submit).toHaveBeenCalledWith(31, 3);
    expect(wrapper.find('[data-testid="save-draft"]').exists()).toBe(false);
    expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it.each(['update', 'submit'])(
    'retains typed content after a 409 from %s and requires a conflict choice',
    async operation => {
      const wrapper = await mountDrawer();
      await wrapper.vm.openDraft(record);
      await wrapper.get('textarea').setValue('My unsaved words.');
      if (operation === 'submit') {
        await wrapper.get('[data-testid="save-draft"]').trigger('click');
        await flushPromises();
      }
      DraftsAPI[operation].mockRejectedValueOnce({
        response: { status: 409, data: { error: 'stale_revision' } },
      });
      DraftsAPI.show.mockResolvedValue({
        data: {
          ...record,
          lock_version: 8,
          definition: {
            ...record.definition,
            body: { text: 'Other administrator.', examples: [] },
          },
        },
      });
      await wrapper
        .get(
          `[data-testid="${operation === 'update' ? 'save' : 'submit'}-draft"]`
        )
        .trigger('click');
      await flushPromises();
      expect(wrapper.get('[data-testid="revision-conflict"]').text()).toContain(
        'DRAFTS.CONFLICT'
      );
      expect(wrapper.get('textarea').element.value).toBe('My unsaved words.');
      expect(
        wrapper.get('[data-testid="save-draft"]').attributes('disabled')
      ).toBeDefined();
      await wrapper.get('[data-testid="keep-changes"]').trigger('click');
      await wrapper.get('[data-testid="save-draft"]').trigger('click');
      await flushPromises();
      expect(DraftsAPI.update).toHaveBeenLastCalledWith(
        31,
        expect.objectContaining({
          lock_version: 8,
          definition: expect.objectContaining({
            body: { text: 'My unsaved words.', examples: [] },
          }),
        })
      );
      wrapper.unmount();
    }
  );

  it('lets the user load the conflicting saved content explicitly', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    DraftsAPI.update.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'stale_revision' } },
    });
    DraftsAPI.show.mockResolvedValue({
      data: {
        ...record,
        lock_version: 7,
        definition: { body: { text: 'Saved by someone else.' } },
      },
    });
    await wrapper.get('textarea').setValue('Mine');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="reload-revision"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe(
      'Saved by someone else.'
    );
    expect(wrapper.find('[data-testid="revision-conflict"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });

  it('keeps a server error visible and preserves unsaved content', async () => {
    const wrapper = await mountDrawer();
    DraftsAPI.create.mockRejectedValueOnce({
      response: { status: 500, data: { message: 'Unavailable' } },
    });
    await wrapper.get('textarea').setValue('Keep this text.');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="meta-error"]').text()).toContain(
      'Unavailable'
    );
    expect(wrapper.get('textarea').element.value).toBe('Keep this text.');
    wrapper.unmount();
  });

  it('creates a local preset with its exact examples and named variables', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.open(null, presetToForm(PRESETS[0]));
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'recordatorio_cita',
        parameter_format: 'NAMED',
        definition: expect.objectContaining({
          body: { text: PRESETS[0].body, examples: PRESETS[0].examples },
        }),
      })
    );
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    expect(DraftsAPI.submit).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uploads to the local owner with its latest revision and removes local media', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    wrapper
      .findComponent('[data-testid="template-header-format"]')
      .vm.$emit('update:modelValue', 'IMAGE');
    await flushPromises();
    DraftsAPI.uploadMedia.mockResolvedValue({
      data: {
        ...record,
        lock_version: 4,
        media: {
          filename: 'photo.png',
          byte_size: 12,
          content_type: 'image/png',
        },
      },
    });
    DraftsAPI.removeMedia.mockResolvedValue({
      data: { ...record, lock_version: 5, media: null },
    });
    const file = new File(['image'], 'photo.png', { type: 'image/png' });
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [file],
    });
    await wrapper.get('input[type="file"]').trigger('change');
    await flushPromises();
    expect(DraftsAPI.uploadMedia).toHaveBeenCalledWith(31, 3, file);
    expect(WhatsappTemplatesAPI.uploadHeaderExample).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('photo.png');
    const remove = wrapper
      .findAll('button')
      .find(
        button =>
          button.attributes('aria-label') ===
          'WHATSAPP_TEMPLATE_MGMT.FORM.REMOVE_FILE'
      );
    await remove.trigger('click');
    await flushPromises();
    expect(DraftsAPI.removeMedia).toHaveBeenCalledWith(31, 4);
    expect(wrapper.text()).not.toContain('photo.png');
    wrapper.unmount();
  });

  it.each(['PENDING', 'APPROVED', 'REJECTED', 'PAUSED'])(
    'opens installed %s in read-only detail and creates a server version',
    async status => {
      const wrapper = await mountDrawer();
      const template = { ...positional, status };
      WhatsappTemplatesAPI.getTemplate.mockResolvedValue({ data: template });
      DraftsAPI.newVersion.mockResolvedValue({ data: record });
      await wrapper.vm.open(template);
      expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-testid="save-draft"]').exists()).toBe(false);
      await wrapper.get('[data-testid="new-version"]').trigger('click');
      await flushPromises();
      expect(DraftsAPI.newVersion).toHaveBeenCalledWith(70, '555');
      expect(wrapper.get('textarea').element.value).toBe(
        record.definition.body.text
      );
      expect(WhatsappTemplatesAPI.updateTemplate).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it('duplicates a saved draft into a different WABA with channel ids', async () => {
    const otherInbox = {
      id: 8,
      channel_id: 80,
      name: 'Sales',
      provider: 'whatsapp_cloud',
      provider_config: { business_account_id: 'waba-b' },
    };
    const wrapper = await mountDrawer({ inboxes: [...inboxes, otherInbox] });
    DraftsAPI.duplicate.mockResolvedValue({
      data: { ...record, id: 32, name: 'appointment_v2' },
    });
    DraftsAPI.show.mockImplementation(async id => ({
      data: { ...record, id, name: id === 32 ? 'appointment_v2' : record.name },
    }));
    await wrapper.vm.openDuplicate({ ...record, isLocalDraft: true });
    const dialog = wrapper
      .findAllComponents(Dialog)
      .find(
        item =>
          item.props('title') === 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.DUPLICATE'
      );
    dialog.findComponent(ComboBox).vm.$emit('update:modelValue', 8);
    await flushPromises();
    dialog.vm.$emit('confirm');
    await flushPromises();
    expect(DraftsAPI.duplicate).toHaveBeenCalledWith(31, {
      preferred_channel_id: 80,
      waba_id: 'waba-b',
    });
    expect(
      wrapper
        .findAll('input')
        .some(input => input.element.value === 'appointment_v2')
    ).toBe(true);
    wrapper.unmount();
  });

  it.each(['reconciling', 'submitted'])(
    'verifies %s without a second creation or submission',
    async status => {
      const wrapper = await mountDrawer();
      DraftsAPI.show.mockResolvedValue({
        data: {
          ...record,
          status,
          submissions: [
            {
              id: 99,
              revision: 2,
              remote_id: 'meta-1',
              remote_status: 'PAUSED',
            },
          ],
        },
      });
      await wrapper.vm.openDraft(record);
      expect(wrapper.get('[data-testid="draft-state"]').text()).toContain(
        status.toUpperCase()
      );
      if (status === 'reconciling')
        expect(wrapper.text()).toContain('DRAFTS.UNCERTAIN');
      expect(wrapper.text()).toContain('DRAFTS.PAUSED');
      await wrapper.get('[data-testid="verify-submission"]').trigger('click');
      await flushPromises();
      expect(DraftsAPI.reconcile).toHaveBeenCalledWith(31, 99);
      expect(DraftsAPI.submit).not.toHaveBeenCalled();
      expect(DraftsAPI.create).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );

  it('keeps opaque components unchanged and blocks submission', async () => {
    const opaque = {
      components: [
        {
          position: 1,
          component: { type: 'CAROUSEL', cards: [{ text: 'opaque' }] },
        },
      ],
      buttons: [],
    };
    DraftsAPI.show.mockResolvedValue({
      data: {
        ...record,
        definition: { ...record.definition, preserved: opaque },
      },
    });
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    expect(wrapper.get('[data-testid="opaque-warning"]').exists()).toBe(true);
    expect(
      wrapper.get('[data-testid="submit-draft"]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.update).toHaveBeenCalledWith(
      31,
      expect.objectContaining({
        definition: expect.objectContaining({ preserved: opaque }),
      })
    );
    wrapper.unmount();
  });

  it('keeps an accepted submission read-only even if the follow-up read fails', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    DraftsAPI.show.mockRejectedValueOnce(new Error('offline'));
    await wrapper.get('[data-testid="submit-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.submit).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-testid="draft-state"]').text()).toContain(
      'SUBMITTING'
    );
    expect(wrapper.find('[data-testid="save-draft"]').exists()).toBe(false);
    expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('does not allow saving a blank replacement after a failed draft load', async () => {
    const wrapper = await mountDrawer();
    DraftsAPI.show.mockRejectedValueOnce(new Error('offline'));
    await wrapper.vm.openDraft(record);
    expect(wrapper.get('[data-testid="meta-error"]').text()).toContain(
      'SAVE_ERROR'
    );
    expect(wrapper.find('[data-testid="save-draft"]').exists()).toBe(false);
    expect(DraftsAPI.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('reopens an incomplete saved draft without truncating its examples', async () => {
    const wrapper = await mountDrawer();
    DraftsAPI.show.mockResolvedValue({
      data: {
        ...record,
        definition: {
          body: { text: 'Unfinished', examples: ['kept', 'also kept'] },
        },
      },
    });
    await wrapper.vm.openDraft(record);
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.update).toHaveBeenCalledWith(
      31,
      expect.objectContaining({
        definition: expect.objectContaining({
          body: { text: 'Unfinished', examples: ['kept', 'also kept'] },
        }),
      })
    );
    wrapper.unmount();
  });

  it('shows the shared WABA destination and clears it when the channel is removed', async () => {
    const wrapper = await mountDrawer({
      inboxes: [
        ...inboxes,
        { ...inboxes[0], id: 8, channel_id: 80, name: 'Sales' },
      ],
    });
    await wrapper.vm.openDraft(record);
    expect(wrapper.text()).toContain('DRAFTS.SHARED');
    wrapper
      .findComponent('[data-testid="template-inbox"]')
      .vm.$emit('update:modelValue', '');
    await flushPromises();
    expect(wrapper.text()).toContain('DRAFTS.NO_DESTINATION_HELP');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.update).toHaveBeenCalledWith(
      31,
      expect.objectContaining({ preferred_channel_id: null, waba_id: null })
    );
    wrapper.unmount();
  });

  it('asks before discarding unsaved content', async () => {
    const wrapper = await mountDrawer();
    await wrapper.get('textarea').setValue('Unsaved');
    await wrapper.vm.close();
    const dialog = wrapper
      .findAllComponents(Dialog)
      .find(
        item =>
          item.props('title') === 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.DISCARD_TITLE'
      );
    await flushPromises();
    expect(dialog.props('description')).toContain('DRAFTS.DISCARD_HELP');
    expect(DraftsAPI.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('prevents submission if its authenticated media could not be loaded', async () => {
    const wrapper = await mountDrawer();
    DraftsAPI.show.mockResolvedValueOnce({
      data: {
        ...record,
        media: {
          filename: 'file.png',
          content_type: 'image/png',
          byte_size: 10,
        },
      },
    });
    DraftsAPI.downloadMedia.mockRejectedValueOnce(new Error('offline'));
    await wrapper.vm.openDraft(record);
    expect(
      wrapper.get('[data-testid="submit-draft"]').attributes('disabled')
    ).toBeDefined();
    expect(DraftsAPI.submit).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
