import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CalendarAppointmentAttributes from '../CalendarAppointmentAttributes.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/calendarAppointmentAttributes.json';
import es from 'dashboard/i18n/locale/es/calendarAppointmentAttributes.json';
import enTypes from 'dashboard/i18n/locale/en/attributesMgmt.json';
import esTypes from 'dashboard/i18n/locale/es/attributesMgmt.json';

const { dispatch } = vi.hoisted(() => ({ dispatch: vi.fn() }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getAppointmentAttributes: vi.fn(),
    updateAppointmentAttributes: vi.fn(),
  },
}));

const KEYS = [
  'ultima_cita',
  'proxima_cita',
  'proxima_cita_titulo',
  'total_citas',
];
const mountSettings = async (locale = 'es') => {
  const wrapper = mount(CalendarAppointmentAttributes, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: { en: { ...en, ...enTypes }, es: { ...es, ...esTypes } },
        }),
      ],
      directives: { tooltip: {} },
    },
  });
  await flushPromises();
  return wrapper;
};
const checkbox = (wrapper, key) =>
  wrapper.get(`[data-testid="appointment-attribute-${key}"] input`);
const saveButton = wrapper =>
  wrapper.get('[data-testid="appointment-attributes-save"]');

describe('CalendarAppointmentAttributes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dispatch.mockResolvedValue();
    CalendarAPI.updateAppointmentAttributes.mockReset();
    CalendarAPI.getAppointmentAttributes.mockResolvedValue({
      data: { keys: null, enabled_keys: [], results: {} },
    });
  });

  it('starts with all checkboxes checked and permits initial activation', async () => {
    const wrapper = await mountSettings();

    KEYS.forEach(key =>
      expect(checkbox(wrapper, key).element.checked).toBe(true)
    );
    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
    expect(saveButton(wrapper).text()).toBe('Actualizar');
    expect(wrapper.text()).toContain('Atributos de cita');
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('loads a saved selection and disables saving until it changes', async () => {
    CalendarAPI.getAppointmentAttributes.mockResolvedValue({
      data: {
        keys: ['total_citas'],
        enabled_keys: ['total_citas'],
        results: {},
      },
    });
    const wrapper = await mountSettings();

    expect(checkbox(wrapper, 'ultima_cita').element.checked).toBe(false);
    expect(checkbox(wrapper, 'total_citas').element.checked).toBe(true);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
    await checkbox(wrapper, 'ultima_cita').setValue(true);
    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('saves the selection and shows created, reused and conflict results', async () => {
    CalendarAPI.updateAppointmentAttributes.mockResolvedValue({
      data: {
        keys: KEYS,
        enabled_keys: KEYS.filter(key => key !== 'ultima_cita'),
        results: {
          ultima_cita: {
            status: 'conflict',
            actual_type: 'text',
            expected_type: 'datetime',
          },
          proxima_cita: {
            status: 'created',
            actual_type: 'datetime',
            expected_type: 'datetime',
          },
          total_citas: {
            status: 'reused',
            actual_type: 'number',
            expected_type: 'number',
          },
        },
      },
    });
    const wrapper = await mountSettings();
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(CalendarAPI.updateAppointmentAttributes).toHaveBeenCalledWith(KEYS);
    expect(dispatch).toHaveBeenCalledWith('attributes/get');
    expect(wrapper.text()).toContain('Creado');
    expect(wrapper.text()).toContain('Ya existía; reutilizado');
    expect(wrapper.text()).toContain('Conflicto de tipo');
    expect(wrapper.text()).toContain('Tipo existente: Texto.');
    expect(checkbox(wrapper, 'ultima_cita').element.checked).toBe(true);
    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('disables all attributes by saving an empty selection', async () => {
    CalendarAPI.updateAppointmentAttributes.mockResolvedValue({
      data: { keys: [], enabled_keys: [], results: {} },
    });
    const wrapper = await mountSettings();
    await Promise.all(KEYS.map(key => checkbox(wrapper, key).setValue(false)));
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(CalendarAPI.updateAppointmentAttributes).toHaveBeenCalledWith([]);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain(
      'se conservan su definición y sus valores'
    );
  });

  it('keeps the selection and permits retry after a save error', async () => {
    CalendarAPI.updateAppointmentAttributes.mockRejectedValue(
      new Error('Failed')
    );
    const wrapper = await mountSettings();
    await checkbox(wrapper, 'total_citas').setValue(false);
    await saveButton(wrapper).trigger('click');
    await flushPromises();

    expect(checkbox(wrapper, 'total_citas').element.checked).toBe(false);
    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith(
      'No se pudieron actualizar los atributos de cita.'
    );
  });

  it('blocks saving when loading fails', async () => {
    CalendarAPI.getAppointmentAttributes.mockRejectedValue(new Error('Failed'));
    const wrapper = await mountSettings();

    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
    expect(
      checkbox(wrapper, 'total_citas').attributes('disabled')
    ).toBeDefined();
  });

  it('renders English labels and explanations', async () => {
    const wrapper = await mountSettings('en');

    expect(wrapper.text()).toContain('Appointment attributes');
    expect(saveButton(wrapper).text()).toBe('Update');
    expect(wrapper.text()).toContain('Dates are stored in UTC');
  });
});
