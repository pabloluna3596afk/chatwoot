import { flushPromises, shallowMount } from '@vue/test-utils';
import CalendarHours from '../CalendarHours.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import { useAlert } from 'dashboard/composables';
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { updateCalendars: vi.fn() },
}));
const calendar = {
  id: 'sales',
  summary: 'Sales',
  enabled: true,
  hour_start: 8,
  hour_end: 20,
  working_days: [1, 2, 3, 4, 5],
  connection: { id: 7 },
};
beforeEach(() => {
  vi.clearAllMocks();
});
describe('Calendar booking hours', () => {
  it('labels the compact start and end fields', () => {
    const wrapper = shallowMount(CalendarHours, {
      props: { calendar },
      global: { mocks: { $t: key => key } },
    });
    const fields = wrapper.findAllComponents(ComboBox);
    expect(fields.map(field => field.props('label'))).toEqual([
      'CITAS_PANEL.START',
      'CITAS_PANEL.END',
    ]);
    expect(
      fields[0].element.parentElement.classList.contains('sm:grid-cols-2')
    ).toBe(true);
    expect(fields[0].element.parentElement.classList.contains('max-w-xs')).toBe(
      true
    );
  });
  it('saves only the selected calendar and adjusts end time when start moves later', async () => {
    CalendarAPI.updateCalendars.mockResolvedValue({
      data: { payload: [{ ...calendar, hour_start: 21, hour_end: 22 }] },
    });
    const wrapper = shallowMount(CalendarHours, {
      props: { calendar },
      global: { mocks: { $t: key => key } },
    });
    wrapper.findAllComponents(ComboBox)[0].vm.$emit('update:modelValue', 21);
    await flushPromises();
    expect(CalendarAPI.updateCalendars).toHaveBeenCalledWith(7, [
      {
        external_id: 'sales',
        summary: 'Sales',
        is_enabled: true,
        hour_start: 21,
        hour_end: 22,
        working_days: [1, 2, 3, 4, 5],
      },
    ]);
    expect(wrapper.emitted('updated')[0][0].hour_end).toBe(22);
  });
  it('saves selected weekdays and keeps at least one day', async () => {
    const wrapper = shallowMount(CalendarHours, {
      props: { calendar: { ...calendar, working_days: [1] } },
      global: { mocks: { $t: key => key } },
    });
    wrapper.findAllComponents(Checkbox)[0].vm.$emit('update:modelValue', false);
    await flushPromises();
    expect(CalendarAPI.updateCalendars).not.toHaveBeenCalled();
    CalendarAPI.updateCalendars.mockResolvedValue({
      data: { payload: [{ ...calendar, working_days: [1, 2] }] },
    });
    wrapper.findAllComponents(Checkbox)[1].vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(
      CalendarAPI.updateCalendars.mock.calls[0][1][0].working_days
    ).toEqual([1, 2]);
  });
  it('preserves displayed data and reports failed writes', async () => {
    CalendarAPI.updateCalendars.mockRejectedValue({
      response: { data: { error: 'Unavailable' } },
    });
    const wrapper = shallowMount(CalendarHours, {
      props: { calendar },
      global: { mocks: { $t: key => key } },
    });
    wrapper.findAllComponents(ComboBox)[1].vm.$emit('update:modelValue', 18);
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.findAllComponents(ComboBox)[1].props('modelValue')).toBe(20);
    expect(useAlert).toHaveBeenCalledWith('Unavailable');
  });
});
