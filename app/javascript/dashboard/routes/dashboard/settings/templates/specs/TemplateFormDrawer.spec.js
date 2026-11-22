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

const mountDrawer = async (props = {}, realPanel = false, attached = false) => {
  const wrapper = mount(TemplateFormDrawer, {
    props: { inboxes, ...props },
    attachTo: realPanel || attached ? document.body : undefined,
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
  it('opens library text read-only, saves button values and submits through the common draft API', async () => {
    const libraryRecord = {
      ...record,
      parameter_format: 'POSITIONAL',
      definition: {
        library: {
          template_name: 'appointment',
          language: 'es',
          preview: {
            body: 'Fixed Meta text',
            buttons: [{ type: 'PHONE_NUMBER', text: 'Call' }],
          },
          button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '' }],
        },
      },
    };
    DraftsAPI.show.mockResolvedValue({ data: structuredClone(libraryRecord) });
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(libraryRecord);
    await flushPromises();
    expect(
      wrapper
        .findComponent('[data-testid="template-language"]')
        .props('disabled')
    ).toBe(true);
    expect(wrapper.get('[data-testid="library-preview"]').text()).toContain(
      'Fixed Meta text'
    );
    expect(wrapper.find('[data-testid="message-editor"]').exists()).toBe(false);
    expect(
      wrapper.get('[data-testid="submit-draft"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper
      .get('[data-testid="library-phone-0"] input')
      .setValue('+593999999999');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.update).toHaveBeenCalledWith(
      31,
      expect.objectContaining({
        definition: {
          library: {
            ...libraryRecord.definition.library,
            button_inputs: [
              { type: 'PHONE_NUMBER', phone_number: '+593999999999' },
            ],
          },
        },
      })
    );
    await wrapper.get('[data-testid="submit-draft"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.submit).toHaveBeenCalledWith(31, expect.any(Number));
    expect(WhatsappTemplatesAPI.createTemplate).not.toHaveBeenCalled();
    wrapper.unmount();
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

  it('groups local status and Meta help without permanent requirements or duplicate draft labels', async () => {
    const wrapper = await mountDrawer();
    const status = wrapper.get('[data-testid="local-save-status"]');
    expect(status.attributes('role')).toBe('status');
    expect(status.classes()).toContain('border-solid');
    expect(status.classes()).toContain('bg-n-alpha-1');
    expect(status.find('[aria-hidden="true"]').exists()).toBe(true);
    expect(status.text()).toContain('DRAFTS.LOCAL_SAVE_HELP');
    expect(status.text()).not.toContain('DRAFTS.NO_DESTINATION_HELP');
    expect(wrapper.text()).not.toContain('DRAFTS.SUBMIT_REQUIREMENTS');
    DraftsAPI.show.mockResolvedValueOnce({
      data: { ...record, preferred_channel_id: null, waba_id: null },
    });
    await wrapper.vm.openDraft(record);
    expect(wrapper.find('[data-testid="draft-state"]').exists()).toBe(false);
    const send = wrapper.get('[data-testid="submit-draft"]');
    expect(send.attributes('title')).toContain('DRAFTS.SUBMIT_REQUIREMENTS');
    wrapper.unmount();
  });

  it('keeps save as the only full-width primary action and the auxiliaries compact', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    const footer = wrapper.get('[data-testid="draft-footer"]');
    expect(footer.classes()).toContain('grid-cols-3');
    expect(footer.get('[data-testid="save-draft"]').classes()).toContain(
      'col-span-3'
    );
    expect(footer.get('[data-testid="save-draft"]').classes()).toContain(
      'bg-n-brand'
    );
    ['submit-draft', 'template-preview-open'].forEach(testId => {
      const button = footer.get(`[data-testid="${testId}"]`);
      expect(button.classes()).not.toContain('w-full');
      expect(button.classes()).not.toContain('bg-n-brand');
      expect(button.text()).not.toBe('');
    });
    expect(footer.get('[data-testid="submit-draft"] span').classes()).toContain(
      'whitespace-normal'
    );
    wrapper.unmount();
  });

  it.each(['save', 'submit'])(
    'announces only the active %s operation and blocks both actions and double clicks',
    async operation => {
      const wrapper = await mountDrawer();
      await wrapper.vm.openDraft(record);
      let resolve;
      const api = operation === 'save' ? DraftsAPI.update : DraftsAPI.submit;
      api.mockImplementationOnce(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const active = wrapper.get(`[data-testid="${operation}-draft"]`);
      await active.trigger('click');
      await active.trigger('click');
      expect(api).toHaveBeenCalledTimes(1);
      const label = operation === 'save' ? 'SAVING' : 'SENDING';
      expect(active.text()).toContain(`DRAFTS.${label}`);
      expect(active.findComponent({ name: 'Spinner' }).exists()).toBe(true);
      const other = wrapper.get(
        `[data-testid="${operation === 'save' ? 'submit' : 'save'}-draft"]`
      );
      expect(other.findComponent({ name: 'Spinner' }).exists()).toBe(false);
      expect(active.attributes('disabled')).toBeDefined();
      expect(other.attributes('disabled')).toBeDefined();
      expect(
        wrapper.get('[data-testid="local-save-status"]').attributes('role')
      ).toBe('status');
      expect(wrapper.get('[data-testid="local-save-status"]').text()).toContain(
        `DRAFTS.${label}`
      );
      resolve({
        data:
          operation === 'save'
            ? record
            : { id: 99, revision: 2, status: 'submitting' },
      });
      await flushPromises();
      wrapper.unmount();
    }
  );

  it('keeps the saved drawer open and offers navigation only through the toast action', async () => {
    const wrapper = await mountDrawer();
    expect(wrapper.get('[data-testid="local-save-status"]').text()).toContain(
      'DRAFTS.LOCAL_DRAFT'
    );
    expect(wrapper.text()).toContain('DRAFTS.LOCAL_SAVE_HELP');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(SidePanelStub.methods.close).not.toHaveBeenCalled();
    expect(wrapper.get('[data-testid="local-save-status"]').text()).toContain(
      'DRAFTS.SAVED_LOCALLY'
    );
    const action = useAlert.mock.calls.at(-1)[1];
    expect(action).toMatchObject({
      type: 'callback',
      message: 'WHATSAPP_TEMPLATE_MGMT.DRAFTS.VIEW_IN_TEMPLATES',
    });
    expect(wrapper.emitted('viewDraft')).toBeUndefined();
    action.onClick();
    expect(wrapper.emitted('viewDraft')[0][0]).toMatchObject({ id: 31 });
    await wrapper
      .get('[data-testid="draft-title"] input')
      .setValue('Changed again');
    expect(wrapper.get('[data-testid="local-save-status"]').text()).toContain(
      'DRAFTS.UNSAVED'
    );
    wrapper.unmount();
  });

  it.each([
    [
      422,
      { error: 'invalid_draft', details: { name: ['has already been taken'] } },
      'IDENTITY_CONFLICT',
    ],
    [409, { error: 'identity_conflict' }, 'IDENTITY_CONFLICT'],
    [
      422,
      {
        error: 'invalid_draft',
        details: { title: ['is invalid'], waba_id: ['is invalid'] },
      },
      'FIELD_ERRORS.title',
    ],
  ])(
    'associates %s errors with readable field messages and focuses the first invalid field',
    async (status, data, key) => {
      const wrapper = await mountDrawer({}, false, true);
      await wrapper.vm.openDraft(record);
      DraftsAPI.update.mockRejectedValueOnce({ response: { status, data } });
      await wrapper.get('[data-testid="save-draft"]').trigger('click');
      await flushPromises();
      const field = wrapper.get('input[aria-invalid="true"]');
      expect(field.element).toBe(document.activeElement);
      const message = wrapper.get(`#${field.attributes('aria-describedby')}`);
      expect(message.text()).toContain(`DRAFTS.${key}`);
      expect(wrapper.get('[data-testid="meta-error"]').text()).not.toContain(
        'waba_id'
      );
      expect(wrapper.get('[data-testid="meta-error"]').text()).not.toContain(
        'invalid_draft'
      );
      wrapper.unmount();
    }
  );

  it('preserves input after a network failure and allows saving again', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    await wrapper.get('textarea').setValue('Keep this message.');
    DraftsAPI.update.mockRejectedValueOnce(new Error('Network Error'));
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="meta-error"]').text()).toContain(
      'FORM.SAVE_ERROR'
    );
    expect(wrapper.get('textarea').element.value).toBe('Keep this message.');
    expect(
      wrapper.get('[data-testid="save-draft"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="meta-error"]').exists()).toBe(false);
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

  it('keeps an optional inbox neutral when opening and saving, and validates only after a send attempt', async () => {
    const wrapper = await mountDrawer({ inboxes: [] });
    const noInbox = { ...record, preferred_channel_id: null, waba_id: null };
    DraftsAPI.show.mockResolvedValueOnce({ data: noInbox });
    await wrapper.vm.openDraft(noInbox);
    expect(
      wrapper
        .get('[data-testid="template-inbox"] button')
        .attributes('aria-invalid')
    ).not.toBe('true');
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="template-inbox"] button')
        .attributes('aria-invalid')
    ).not.toBe('true');
    expect(wrapper.text()).not.toContain('FORM.ERRORS.CHANNEL_REQUIRED');
    const send = wrapper.get('[data-testid="submit-draft"]');
    expect(send.attributes('disabled')).toBeUndefined();
    await send.trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="template-inbox"] button')
        .attributes('aria-invalid')
    ).toBe('true');
    expect(DraftsAPI.submit).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="save-draft"]').trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-testid="template-inbox"] button')
        .attributes('aria-invalid')
    ).toBe('true');
    wrapper.unmount();
  });

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
      'WHATSAPP_TEMPLATE_MGMT.DRAFTS.SAVED',
      expect.objectContaining({ type: 'callback' })
    );
    expect(
      wrapper.get('[data-testid="submit-draft"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('enables secondary submit after saving a valid draft; save stays primary and local', async () => {
    const wrapper = await mountDrawer();
    await wrapper.vm.openDraft(record);
    expect(wrapper.get('[data-testid="submit-draft"]').classes()).not.toContain(
      'bg-n-brand'
    );
    expect(wrapper.get('[data-testid="save-draft"]').classes()).toContain(
      'bg-n-brand'
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
    await wrapper.vm.open(
      null,
      presetToForm({ ...PRESETS[0], title: 'Recordatorio de cita' })
    );
    expect(DraftsAPI.create).not.toHaveBeenCalled();
    expect(wrapper.get('[data-testid="draft-title"] input').element.value).toBe(
      'Recordatorio de cita'
    );
    expect(wrapper.get('[data-testid="draft-title"]').text()).toContain(
      'DRAFTS.INTERNAL_TITLE_HELP'
    );
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
