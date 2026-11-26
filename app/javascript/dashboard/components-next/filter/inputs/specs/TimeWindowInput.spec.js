import { mount } from '@vue/test-utils';
import TimeWindowInput from '../TimeWindowInput.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      ({
        'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Todos los días',
        'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Lun a vie',
        'DAYS_OF_WEEK.MONDAY': 'Lunes',
      })[key] || key,
  }),
}));

const mountInput = (modelValue = '') =>
  mount(TimeWindowInput, {
    props: { modelValue },
    global: { stubs: { Teleport: true } },
  });

const lastEmitted = wrapper => wrapper.emitted('update:modelValue')?.at(-1)[0];

const typeTime = async (wrapper, index, value) => {
  const input = wrapper.findAll('input')[index];
  await input.setValue(value);
  await input.trigger('blur');
};

describe('TimeWindowInput', () => {
  it('shows a saved window, including its weekdays', () => {
    const wrapper = mountInput('22:00-06:00|fri,sat');
    const inputs = wrapper.findAll('input');
    expect(inputs[0].element.value).toBe('22:00');
    expect(inputs[1].element.value).toBe('06:00');
    const pressed = wrapper
      .findAll('button[aria-pressed="true"]')
      .map(button => button.attributes('aria-label'));
    expect(pressed).toEqual(['DAYS_OF_WEEK.FRIDAY', 'DAYS_OF_WEEK.SATURDAY']);
    wrapper.unmount();
  });

  it('emits nothing until both times are set, then the window', async () => {
    const wrapper = mountInput();
    await typeTime(wrapper, 0, '18:00');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    await typeTime(wrapper, 1, '08:00');
    expect(lastEmitted(wrapper)).toBe('18:00-08:00');
    wrapper.unmount();
  });

  it('adds and removes weekdays in calendar order', async () => {
    const wrapper = mountInput('09:00-13:00');
    const buttons = wrapper.findAll('button[aria-pressed]');
    // The DOM follows the calendar: sun, mon, tue, ...
    await buttons[2].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|tue');
    await buttons[1].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|mon,tue');
    await buttons[2].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|mon');
    await buttons[1].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00');
    wrapper.unmount();
  });

  it('follows a value changed from outside', async () => {
    const wrapper = mountInput('09:00-13:00');
    await wrapper.setProps({ modelValue: '' });
    expect(wrapper.findAll('input')[0].element.value).toBe('');
    await wrapper.setProps({ modelValue: '20:00-07:30|sun' });
    expect(wrapper.findAll('input')[1].element.value).toBe('07:30');
    wrapper.unmount();
  });

  it('shows a readable summary for an overnight window and its selected days', () => {
    const wrapper = mountInput('22:00-06:00|mon,tue,wed,thu,fri');
    expect(wrapper.text()).toContain('22:00–06:00 · Lun a vie');
    wrapper.unmount();
  });
});
