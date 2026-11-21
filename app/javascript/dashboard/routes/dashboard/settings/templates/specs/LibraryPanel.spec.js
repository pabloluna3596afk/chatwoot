import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import LibraryPanel from '../LibraryPanel.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
import DraftsAPI from 'dashboard/api/whatsappTemplateDrafts';
import { useAlert } from 'dashboard/composables';
import spanish from 'dashboard/i18n/locale/es/whatsappTemplateMgmt.json';
import english from 'dashboard/i18n/locale/en/whatsappTemplateMgmt.json';

const translate = (key, params = {}) => {
  const message = key
    .split('.')
    .reduce((value, part) => value?.[part], spanish);
  return Object.entries(params).reduce(
    (value, [name, replacement]) => value.replace(`{${name}}`, replacement),
    message || key
  );
};

vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return {
    useI18n: () => ({ t: translate, te: () => false, locale: ref('es') }),
  };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { locale: 'es' } } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappTemplates', () => ({
  default: { library: vi.fn(), createFromLibrary: vi.fn() },
}));

vi.mock('dashboard/api/whatsappTemplateDrafts', () => ({
  default: { fromLibrary: vi.fn() },
}));

const entries = [
  {
    name: 'appointment_reminder',
    language: 'es',
    category: 'UTILITY',
    body: 'Recordatorio de cita',
    buttons: [{ type: 'PHONE_NUMBER', text: 'Llamar' }],
  },
];

const mountPanel = async (props = {}) => {
  const wrapper = mount(LibraryPanel, {
    props: { inboxes: [{ id: 5, channel_id: 50, name: 'Soporte' }], ...props },
    global: {
      mocks: { $t: translate },
    },
  });
  await flushPromises();
  return wrapper;
};

enableAutoUnmount(afterEach);

describe('LibraryPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    WhatsappTemplatesAPI.library.mockReset();
    DraftsAPI.fromLibrary.mockReset();
    DraftsAPI.fromLibrary.mockResolvedValue({
      data: { id: 31, definition: { library: {} } },
    });
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: entries, next: null, language_used: 'es' },
    });
  });

  it('loads all pages before counting and paginates only the visible rows', async () => {
    WhatsappTemplatesAPI.library
      .mockResolvedValueOnce({
        data: {
          templates: Array.from({ length: 12 }, (_, index) => ({
            ...entries[0],
            name: `reminder_${index}`,
          })),
          next: 'abc',
          language_used: 'es',
        },
      })
      .mockResolvedValueOnce({
        data: {
          templates: [{ ...entries[0], name: 'last_reminder' }],
          next: null,
          language_used: 'es',
        },
      });
    const wrapper = await mountPanel();
    expect(WhatsappTemplatesAPI.library).toHaveBeenNthCalledWith(
      1,
      5,
      { after: undefined },
      { signal: expect.any(AbortSignal) }
    );
    expect(WhatsappTemplatesAPI.library).toHaveBeenNthCalledWith(
      2,
      5,
      { after: 'abc' },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      translate('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE_USED', {
        language: 'Espa\u00f1ol',
      })
    );
    const filter = wrapper.findComponent(FilterDropdown);
    expect(
      filter.props('options').find(option => option.value === 'es').count
    ).toBe(13);
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(12);
    await wrapper.get('[data-testid="library-more"]').trigger('click');
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(13);
    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('counts both filters under search and the other selection, keeps zeros and all totals', async () => {
    WhatsappTemplatesAPI.library.mockImplementation(async id => ({
      data: {
        templates:
          id === 5
            ? [
                ...entries,
                { ...entries[0], name: 'appointment_english', language: 'en' },
                {
                  ...entries[0],
                  name: 'delivery',
                  language: 'en',
                  body: 'Delivery',
                },
              ]
            : [{ ...entries[0], name: 'appointment_sales' }],
        next: null,
      },
    }));
    const wrapper = await mountPanel({
      inboxes: [
        { id: 5, channel_id: 50, name: 'Soporte' },
        { id: 6, channel_id: 60, name: 'Ventas' },
      ],
    });
    const [languages, inboxes] = wrapper.findAllComponents(FilterDropdown);
    expect(
      languages.props('options').find(option => option.value === 'all').count
    ).toBe(3);
    expect(
      languages.props('options').find(option => option.value === 'en').count
    ).toBe(2);
    expect(
      languages.props('options').find(option => option.value === 'fr').count
    ).toBe(0);
    expect(inboxes.props('options').map(option => option.count)).toEqual([
      2, 1, 1,
    ]);
    inboxes.vm.$emit('update:modelValue', 6);
    await flushPromises();
    expect(
      languages.props('options').find(option => option.value === 'all').count
    ).toBe(1);
    expect(
      languages.props('options').find(option => option.value === 'en').count
    ).toBe(0);
    expect(inboxes.props('options').map(option => option.count)).toEqual([
      2, 1, 1,
    ]);
    languages.vm.$emit('update:modelValue', 'all');
    await flushPromises();
    expect(inboxes.props('options').map(option => option.count)).toEqual([
      4, 3, 1,
    ]);
    inboxes.vm.$emit('update:modelValue', 'all');
    await wrapper
      .get('[data-testid="library-search"] input')
      .setValue('appointment');
    expect(
      languages.props('options').find(option => option.value === 'all').count
    ).toBe(3);
    expect(
      languages.props('options').find(option => option.value === 'en').count
    ).toBe(1);
    expect(inboxes.props('options').map(option => option.count)).toEqual([
      3, 2, 1,
    ]);
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(3);
    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledTimes(2);
    await wrapper
      .get('[data-testid="library-search"] input')
      .setValue('not found');
    expect(languages.props('options').every(option => option.count === 0)).toBe(
      true
    );
    expect(inboxes.props('options').every(option => option.count === 0)).toBe(
      true
    );
    wrapper.unmount();
  });

  it('keeps the selected template destination when all inboxes are visible', async () => {
    WhatsappTemplatesAPI.library.mockImplementation(async id => ({
      data: {
        templates: [{ ...entries[0], name: `reminder_${id}`, buttons: [] }],
        next: null,
      },
    }));
    const wrapper = await mountPanel({
      inboxes: [
        { id: 5, channel_id: 50, name: 'Soporte' },
        { id: 6, channel_id: 60, name: 'Ventas' },
      ],
    });
    wrapper
      .findAllComponents(FilterDropdown)[1]
      .vm.$emit('update:modelValue', 'all');
    await flushPromises();
    await wrapper.findAll('[data-testid="library-use"]')[1].trigger('click');
    await flushPromises();
    expect(DraftsAPI.fromLibrary).toHaveBeenCalledWith(
      expect.objectContaining({
        channel_id: 60,
        library_template_name: 'reminder_6',
        language: 'es',
      })
    );
    wrapper.unmount();
  });

  it('does not replace a new catalog with a superseded response', async () => {
    let resolveOld;
    WhatsappTemplatesAPI.library.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = await mountPanel();
    await wrapper.setProps({
      inboxes: [{ id: 5, name: 'Soporte actualizado' }],
    });
    await flushPromises();
    resolveOld({
      data: {
        templates: [{ ...entries[0], name: 'stale' }],
        next: null,
        language_used: 'en_US',
      },
    });
    await flushPromises();
    wrapper
      .findAllComponents(FilterDropdown)[0]
      .vm.$emit('update:modelValue', 'all');
    await flushPromises();
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(1);
    expect(wrapper.text()).not.toContain('stale');
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      translate('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE_USED', {
        language: 'Espa\u00f1ol',
      })
    );
    wrapper.unmount();
  });

  it('lists the complete catalog and displays the response language', async () => {
    const wrapper = await mountPanel();

    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledWith(
      5,
      { after: undefined },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(1);
    expect(wrapper.find('[data-testid="library-more"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Idioma de la biblioteca: Español'
    );
  });

  it('shows the actual mapped language without changing the requested language', async () => {
    const wrapper = await mountPanel({
      templates: [{ language: 'es_EC', inboxes: [{ id: 5 }] }],
    });

    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledWith(
      5,
      { after: undefined },
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.findComponent(FilterDropdown).props('modelValue')).toBe(
      'es_EC'
    );
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Idioma de la biblioteca: Español'
    );
    wrapper.unmount();
  });

  it('shows the US English fallback returned by Meta', async () => {
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: [], next: null, language_used: 'en_US' },
    });
    const wrapper = await mountPanel();

    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Idioma de la biblioteca: Inglés estadounidense'
    );
  });

  it('shows all languages when Meta was queried without a language', async () => {
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: entries, next: null, language_used: null },
    });
    const wrapper = await mountPanel();

    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Se muestran plantillas de la biblioteca en todos los idiomas disponibles.'
    );
  });

  it('keeps the response language for each inbox when changing the counted inbox filter', async () => {
    WhatsappTemplatesAPI.library.mockImplementation(async id => ({
      data: {
        templates: entries,
        next: null,
        language_used: id === 5 ? 'es' : 'en_US',
      },
    }));
    const wrapper = await mountPanel({
      inboxes: [
        { id: 5, channel_id: 50, name: 'Soporte' },
        { id: 6, channel_id: 60, name: 'Ventas' },
      ],
    });
    const inboxes = wrapper.findAllComponents(FilterDropdown)[1];
    inboxes.vm.$emit('update:modelValue', 6);
    await flushPromises();
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      translate('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.LANGUAGE_USED', {
        language: 'Ingl\u00e9s estadounidense',
      })
    );
    inboxes.vm.$emit('update:modelValue', 'all');
    await flushPromises();
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      translate('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.ALL_LANGUAGES')
    );
    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledTimes(2);
  });

  it('shows the real Meta error in Spanish context', async () => {
    WhatsappTemplatesAPI.library.mockRejectedValue({
      response: { data: { message: 'Invalid topic' } },
    });
    const wrapper = await mountPanel();

    expect(wrapper.get('[data-testid="library-error"]').text()).toBe(
      'No se pudo consultar la biblioteca de Meta: Invalid topic'
    );
    expect(wrapper.find('[data-testid="library-language-used"]').exists()).toBe(
      false
    );
  });

  it('uses the translated error when no Meta message is available', async () => {
    WhatsappTemplatesAPI.library.mockRejectedValue(new Error('down'));
    const wrapper = await mountPanel();

    expect(wrapper.get('[data-testid="library-error"]').text()).toBe(
      'No se pudo consultar la biblioteca de Meta. Inténtalo de nuevo.'
    );
  });

  it('keeps English and Spanish library keys in sync', () => {
    const es = spanish.WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY;
    const en = english.WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY;

    expect(Object.keys(es).sort()).toEqual(Object.keys(en).sort());
    expect(Object.keys(es.DIALOG).sort()).toEqual(
      Object.keys(en.DIALOG).sort()
    );
  });

  it('says so when Meta has nothing, or cannot be read', async () => {
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: [], next: null },
    });
    expect(
      (await mountPanel()).find('[data-testid="library-empty"]').exists()
    ).toBe(true);

    WhatsappTemplatesAPI.library.mockRejectedValue(new Error('down'));
    expect(
      (await mountPanel()).find('[data-testid="library-error"]').exists()
    ).toBe(true);
  });

  it('creates a local draft with a read-only preview and incomplete button inputs, and opens that draft', async () => {
    const wrapper = await mountPanel();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    await flushPromises();
    expect(DraftsAPI.fromLibrary).toHaveBeenCalledWith({
      channel_id: 50,
      library_template_name: 'appointment_reminder',
      name: 'appointment_reminder',
      language: 'es',
      category: 'UTILITY',
      button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '' }],
      preview: { body: entries[0].body, buttons: entries[0].buttons },
    });
    expect(wrapper.emitted('created')).toEqual([
      [{ id: 31, definition: { library: {} } }],
    ]);
    expect(WhatsappTemplatesAPI.createFromLibrary).not.toHaveBeenCalled();
  });

  it('blocks duplicate clicks while creating a draft', async () => {
    let resolve;
    DraftsAPI.fromLibrary.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = await mountPanel();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    expect(DraftsAPI.fromLibrary).toHaveBeenCalledTimes(1);
    resolve({ data: { id: 31 } });
    await flushPromises();
    expect(wrapper.emitted('created')).toEqual([[{ id: 31 }]]);
  });

  it('uses the library response language when the entry omits it', async () => {
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: {
        templates: [
          { name: 'reminder', category: 'UTILITY', body: 'Reminder' },
        ],
        next: null,
        language_used: 'en_US',
      },
    });
    const wrapper = await mountPanel();
    wrapper.findComponent(FilterDropdown).vm.$emit('update:modelValue', 'all');
    await flushPromises();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    await flushPromises();

    expect(DraftsAPI.fromLibrary).toHaveBeenCalledWith(
      expect.objectContaining({ language: 'en_US' })
    );
    expect(wrapper.emitted('created')).toHaveLength(1);
  });

  it('shows the draft creation error and leaves the catalog available', async () => {
    DraftsAPI.fromLibrary.mockRejectedValue({
      response: { data: { message: 'Este nombre ya existe.' } },
    });
    const wrapper = await mountPanel();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Este nombre ya existe.');
    expect(wrapper.emitted('created')).toBeUndefined();
    expect(wrapper.find('[data-testid="library-use"]').exists()).toBe(true);
  });
});
