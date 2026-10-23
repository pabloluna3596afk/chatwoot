import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import DateField from '../DateField.vue';

const mountField = (props = {}, locale = 'es') =>
  mount(DateField, {
    props: { label: 'Fecha', modelValue: '2030-01-15', ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale, messages: {} })],
      stubs: { Teleport: true },
    },
  });
afterEach(() => {
  vi.useRealTimers();
});
describe('DateField', () => {
  it.each([
    ['es', '15/01/2030'],
    ['en', '01/15/2030'],
  ])('formats %s and emits an ISO date', async (locale, text) => {
    const wrapper = mountField({}, locale);
    expect(wrapper.text()).toContain(text);
    await wrapper.get('[aria-haspopup]').trigger('click');
    await wrapper.get('[aria-label="2030-01-16"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['2030-01-16']]);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('disables dates before min and marks today and the selected day', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2030, 0, 15, 12));
    const wrapper = mountField({ min: '2030-01-14' });
    await wrapper.get('[aria-haspopup]').trigger('click');
    expect(
      wrapper.get('[aria-label="2030-01-13"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[aria-current="date"]').attributes('aria-pressed')
    ).toBe('true');
    await wrapper.get('[aria-label="2030-01-13"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
  it('moves between months across a year and closes with Escape', async () => {
    const wrapper = mountField();
    await wrapper.get('[aria-haspopup]').trigger('click');
    await wrapper
      .get('[aria-label="DATE_FIELD.PREVIOUS_MONTH"]')
      .trigger('click');
    expect(wrapper.find('[aria-label="2029-12-31"]').exists()).toBe(true);
    await wrapper.get('[aria-label="DATE_FIELD.NEXT_MONTH"]').trigger('click');
    expect(wrapper.find('[aria-label="2030-01-31"]').exists()).toBe(true);
    await wrapper.get('[aria-haspopup]').trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });
});
