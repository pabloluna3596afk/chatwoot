import { flushPromises, mount } from '@vue/test-utils';
import LibraryPanel from '../LibraryPanel.vue';
import FilterDropdown from 'dashboard/components-next/filter-dropdown/FilterDropdown.vue';
import WhatsappTemplatesAPI from 'dashboard/api/whatsappTemplates';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, te: () => false, locale: { value: 'es' } }),
}));
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
      data: { templates: entries, next: null },
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
        },
      })
      .mockResolvedValueOnce({
        data: {
          templates: [{ ...entries[0], name: 'last_reminder' }],
          next: null,
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
        { id: 5, name: 'Soporte' },
        { id: 6, name: 'Ventas' },
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
        { id: 5, name: 'Soporte' },
        { id: 6, name: 'Ventas' },
      ],
    });
    wrapper
      .findAllComponents(FilterDropdown)[1]
      .vm.$emit('update:modelValue', 'all');
    await flushPromises();
    await wrapper.findAll('[data-testid="library-use"]')[1].trigger('click');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();
    expect(WhatsappTemplatesAPI.createFromLibrary).toHaveBeenCalledWith(
      6,
      expect.objectContaining({
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
    await wrapper.setProps({ inboxes: [{ id: 6, name: 'Ventas' }] });
    await flushPromises();
    resolveOld({
      data: { templates: [{ ...entries[0], name: 'stale' }], next: null },
    });
    await flushPromises();
    wrapper
      .findAllComponents(FilterDropdown)[0]
      .vm.$emit('update:modelValue', 'all');
    expect(wrapper.text()).not.toContain('stale');
    wrapper.unmount();
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
