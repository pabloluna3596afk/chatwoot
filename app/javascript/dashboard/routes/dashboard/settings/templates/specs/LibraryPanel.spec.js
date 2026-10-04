import { flushPromises, mount } from '@vue/test-utils';
import LibraryPanel from '../LibraryPanel.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false }),
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

const mountPanel = async () => {
  const wrapper = mount(LibraryPanel, {
    props: { inboxes: [{ id: 5, name: 'Soporte' }] },
    global: {
      mocks: { $t: key => key },
      stubs: { Dialog: DialogStub },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('LibraryPanel', () => {
  beforeEach(() => {
    WhatsappTemplatesAPI.library.mockReset();
    WhatsappTemplatesAPI.createFromLibrary.mockReset();
    WhatsappTemplatesAPI.library.mockResolvedValue({
      data: { templates: entries, next: 'abc' },
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
      data: { id: '1' },
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
  });
});
