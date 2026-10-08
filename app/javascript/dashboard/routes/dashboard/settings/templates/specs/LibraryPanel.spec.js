import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import LibraryPanel from '../LibraryPanel.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';
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

const DialogStub = {
  template: '<div><slot /></div>',
  emits: ['confirm'],
  methods: { open: vi.fn(), close: vi.fn() },
};

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
    props: { inboxes: [{ id: 5, name: 'Soporte' }], ...props },
    global: {
      mocks: { $t: translate },
      stubs: { Dialog: DialogStub },
    },
  });
  await flushPromises();
  return wrapper;
};

enableAutoUnmount(afterEach);

describe('LibraryPanel', () => {
  beforeEach(() => {
    WhatsappTemplatesAPI.library.mockReset();
    WhatsappTemplatesAPI.createFromLibrary.mockReset();
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: entries, next: 'abc', language_used: 'es' },
    });
  });

  it('lists the library in the chosen language and offers more', async () => {
    const wrapper = await mountPanel();

    expect(WhatsappTemplatesAPI.library).toHaveBeenCalledWith(5, {
      search: undefined,
      language: 'es',
      after: undefined,
    });
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(1);
    expect(wrapper.find('[data-testid="library-more"]').exists()).toBe(true);
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
      expect.objectContaining({ language: 'es_EC' })
    );
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Idioma de la biblioteca: Español'
    );
    wrapper.unmount();
  });

  it('keeps the next cursor and actual language when loading another page', async () => {
    const wrapper = await mountPanel();
    WhatsappTemplatesAPI.library.mockResolvedValueOnce({
      data: {
        templates: [{ ...entries[0], name: 'second_reminder' }],
        next: null,
        language_used: 'es',
      },
    });

    await wrapper.get('[data-testid="library-more"]').trigger('click');
    await flushPromises();

    expect(WhatsappTemplatesAPI.library).toHaveBeenLastCalledWith(5, {
      search: undefined,
      language: 'es',
      after: 'abc',
    });
    expect(wrapper.findAll('[data-testid="library-item"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="library-more"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="library-language-used"]').text()).toBe(
      'Idioma de la biblioteca: Español'
    );
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

  it('creates from the library with the name, the library name and the values its buttons ask for', async () => {
    WhatsappTemplatesAPI.createFromLibrary.mockResolvedValue({
      data: { id: '1', language_used: 'es' },
    });
    const wrapper = await mountPanel();

    await wrapper.get('[data-testid="library-use"]').trigger('click');
    const inputs = wrapper.findAll('input');
    await inputs[inputs.length - 1].setValue('+593999999999');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(WhatsappTemplatesAPI.createFromLibrary).toHaveBeenCalledWith(5, {
      library_template_name: 'appointment_reminder',
      name: 'appointment_reminder',
      language: 'es',
      category: 'UTILITY',
      button_inputs: [{ type: 'PHONE_NUMBER', phone_number: '+593999999999' }],
    });
    expect(wrapper.emitted('created')).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith(
      'Plantilla enviada a Meta en Español.'
    );
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
    WhatsappTemplatesAPI.createFromLibrary.mockResolvedValue({
      data: { id: '1', language_used: 'en_US' },
    });
    const wrapper = await mountPanel();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(WhatsappTemplatesAPI.createFromLibrary).toHaveBeenCalledWith(
      5,
      expect.objectContaining({ language: 'en_US' })
    );
    expect(useAlert).toHaveBeenCalledWith(
      'Plantilla enviada a Meta en Inglés estadounidense.'
    );
  });

  it('shows the real Meta creation error and keeps the dialog open', async () => {
    WhatsappTemplatesAPI.createFromLibrary.mockRejectedValue({
      response: { data: { message: 'Este nombre ya existe.' } },
    });
    const wrapper = await mountPanel();
    await wrapper.get('[data-testid="library-use"]').trigger('click');
    const inputs = wrapper.findAll('input');
    await inputs[inputs.length - 1].setValue('+593999999999');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Este nombre ya existe.');
    expect(wrapper.emitted('created')).toBeUndefined();
    expect(DialogStub.methods.close).not.toHaveBeenCalled();
  });
});
