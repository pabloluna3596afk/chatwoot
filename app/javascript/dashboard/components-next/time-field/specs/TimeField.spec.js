import { mount } from '@vue/test-utils';
import TimeField from '../TimeField.vue';
const mountField = (props = {}) =>
  mount(TimeField, {
    props: { label: 'Hora', modelValue: '10:00', ...props },
    global: { stubs: { Teleport: true } },
  });
describe('TimeField', () => {
  it('offers every quarter hour and selects without changing the value format', async () => {
    const wrapper = mountField();
    await wrapper.get('input').trigger('click');
    expect(wrapper.findAll('[role="option"]')).toHaveLength(96);
    expect(wrapper.get('[data-centered="true"]').text()).toBe('10:00');
    await wrapper
      .findAll('[role="option"]')
      .find(option => option.text() === '10:15')
      .trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['10:15']]);
    expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('validates typed HH:mm on blur, rejecting invalid hours', async () => {
    const wrapper = mountField();
    await wrapper.get('input').setValue('23:59');
    await wrapper.get('input').trigger('blur');
    expect(wrapper.emitted('update:modelValue')).toEqual([['23:59']]);
    await wrapper.get('input').setValue('25:61');
    await wrapper.get('input').trigger('blur');
    expect(wrapper.get('input').attributes('aria-invalid')).toBe('true');
    expect(wrapper.emitted('update:modelValue')).toHaveLength(1);
    expect(wrapper.get('input').element.value).toBe('10:00');
    wrapper.unmount();
  });
  it('centers the list on the current quarter hour without a selection', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2030, 0, 15, 14, 30));
    const wrapper = mountField({ modelValue: '' });
    await wrapper.get('input').trigger('click');
    expect(wrapper.get('[data-centered="true"]').text()).toBe('14:30');
    wrapper.unmount();
    vi.useRealTimers();
  });
});
