import { mount } from '@vue/test-utils';
import TimeWindowInput from '../TimeWindowInput.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const translated = {
        'AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS': 'Todos los días',
        'AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS': 'Lun a vie',
        'AUTOMATION.TIME_WINDOW.SUMMARY_EMPTY':
          'Elige la hora de inicio y de fin.',
        'AUTOMATION.TIME_WINDOW.SUMMARY_IN': `Se cumple de ${params?.from} a ${params?.to} · ${params?.days}`,
        'AUTOMATION.TIME_WINDOW.SUMMARY_OUT': `Se cumple fuera de ${params?.from} a ${params?.to} · ${params?.days}`,
        'AUTOMATION.TIME_WINDOW.INBOX_TIME_ZONE': 'hora de la bandeja',
        'AUTOMATION.TIME_WINDOW.OVERNIGHT': 'cruza la medianoche',
        'AUTOMATION.TIME_WINDOW.ERROR_SAME':
          'La hora de fin debe ser distinta de la de inicio.',
        'AUTOMATION.TIME_WINDOW.MIN_DAY': 'Elige al menos un día.',
        'AUTOMATION.TIME_WINDOW.WEEKDAYS': 'Lun a vie',
        'AUTOMATION.TIME_WINDOW.ALL': 'Todos',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_SUN': 'Dom',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_MON': 'Lun',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_TUE': 'Mar',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_WED': 'Mié',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_THU': 'Jue',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_FRI': 'Vie',
        'AUTOMATION.TIME_WINDOW.DAY_SHORT_SAT': 'Sáb',
        'DAYS_OF_WEEK.SUNDAY': 'Domingo',
        'DAYS_OF_WEEK.MONDAY': 'Lunes',
        'DAYS_OF_WEEK.TUESDAY': 'Martes',
        'DAYS_OF_WEEK.WEDNESDAY': 'Miércoles',
        'DAYS_OF_WEEK.THURSDAY': 'Jueves',
        'DAYS_OF_WEEK.FRIDAY': 'Viernes',
        'DAYS_OF_WEEK.SATURDAY': 'Sábado',
      }[key];
      return translated || key;
    },
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
    expect(pressed).toEqual(['Viernes', 'Sábado']);
    wrapper.unmount();
  });

  it('rehydrates an array payload and shows no suffix as every day', () => {
    const wrapper = mountInput(['18:00-08:00']);
    expect(wrapper.findAll('button[aria-pressed="true"]')).toHaveLength(7);
    expect(wrapper.text()).toContain(
      'Se cumple de 18:00 a 08:00 · Todos los días'
    );
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
    const wrapper = mountInput('09:00-13:00|mon,tue');
    const buttons = wrapper.findAll('button[aria-pressed]');
    // The DOM follows the calendar: sun, mon, tue, ...
    await buttons[2].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|mon');
    await buttons[5].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|mon,fri');
    await buttons[1].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|fri');
    await buttons[5].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|fri');
    wrapper.unmount();
  });

  it('keeps the last selected day selected and exposes its reason', async () => {
    const wrapper = mountInput('09:00-13:00|mon');
    const monday = wrapper.find('button[aria-label="Lunes"]');
    expect(monday.attributes('aria-disabled')).toBe('true');
    await monday.trigger('click');
    expect(monday.attributes('aria-pressed')).toBe('true');
    expect(monday.attributes('title')).toBe('Elige al menos un día.');
    wrapper.unmount();
  });

  it('provides weekday and all-day shortcuts', async () => {
    const wrapper = mountInput('09:00-13:00|sat');
    const shortcuts = wrapper
      .findAll('button')
      .filter(button => ['Lun a vie', 'Todos'].includes(button.text()));
    await shortcuts[0].trigger('click');
    expect(lastEmitted(wrapper)).toBe('09:00-13:00|mon,tue,wed,thu,fri');
    await shortcuts[1].trigger('click');
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
    expect(wrapper.text()).toContain(
      'Se cumple de 22:00 a 06:00 · Lun a vie · cruza la medianoche · hora de la bandeja'
    );
    wrapper.unmount();
  });

  it('always shows one summary line, including empty and same-time states', async () => {
    const wrapper = mountInput();
    expect(wrapper.text()).toContain('Elige la hora de inicio y de fin.');
    await typeTime(wrapper, 0, '09:00');
    await typeTime(wrapper, 1, '09:00');
    expect(wrapper.text()).toContain(
      'La hora de fin debe ser distinta de la de inicio.'
    );
    expect(wrapper.findAll('p[aria-live="polite"]')).toHaveLength(1);
    expect(
      wrapper.findAll('input').map(input => input.attributes('aria-invalid'))
    ).toEqual(['true', 'true']);
    wrapper.unmount();
  });
});
