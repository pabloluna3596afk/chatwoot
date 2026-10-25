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
    await wrapper.get('[data-date="2030-01-16"]').trigger('click');
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
      wrapper.get('[data-date="2030-01-13"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[aria-current="date"]').attributes('aria-pressed')
    ).toBe('true');
    await wrapper.get('[data-date="2030-01-13"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
  it('moves between months across a year and closes with Escape', async () => {
    const wrapper = mountField();
    await wrapper.get('[aria-haspopup]').trigger('click');
    await wrapper
      .get('[aria-label="DATE_FIELD.PREVIOUS_MONTH"]')
      .trigger('click');
    expect(wrapper.find('[data-date="2029-12-31"]').exists()).toBe(true);
    await wrapper.get('[aria-label="DATE_FIELD.NEXT_MONTH"]').trigger('click');
    expect(wrapper.find('[data-date="2030-01-31"]').exists()).toBe(true);
    await wrapper.get('[aria-haspopup]').trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    wrapper.unmount();
  });
});

it('moves days across months using arrows, selects ISO and restores focus, while Tab is free', async () => {
  const wrapper = mount(DateField, {
    attachTo: document.body,
    props: { label: 'Date', modelValue: '2030-01-31', min: '2030-01-30' },
  });
  const trigger = wrapper.get('[aria-haspopup]');
  await trigger.trigger('click');
  await flushPromises();
  expect(document.activeElement.dataset.date).toBe('2030-01-31');
  document.activeElement.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'ArrowRight',
      bubbles: true,
      cancelable: true,
    })
  );
  await flushPromises();
  expect(document.activeElement.dataset.date).toBe('2030-02-01');
  expect(document.activeElement.getAttribute('aria-label')).toContain('2030');
  document.activeElement.click();
  await flushPromises();
  expect(wrapper.emitted('update:modelValue')).toEqual([['2030-02-01']]);
  expect(document.activeElement).toBe(trigger.element);
  await trigger.trigger('click');
  await flushPromises();
  const tab = new KeyboardEvent('keydown', {
    key: 'Tab',
    bubbles: true,
    cancelable: true,
  });
  document.activeElement.dispatchEvent(tab);
  expect(tab.defaultPrevented).toBe(false);
  document.activeElement.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
  );
  await flushPromises();
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  wrapper.unmount();
});

it('moves horizontally with the visual neighbor in RTL', async () => {
  const app = document.createElement('div');
  app.id = 'app';
  app.dir = 'rtl';
  document.body.appendChild(app);
  const wrapper = mount(DateField, {
    attachTo: app,
    props: { label: 'Date', modelValue: '2030-01-15' },
  });
  try {
    await wrapper.get('[aria-haspopup]').trigger('click');
    await flushPromises();
    const selectedDate = document.querySelector('[data-date="2030-01-15"]');
    selectedDate.focus();

    selectedDate.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'ArrowLeft',
        bubbles: true,
        cancelable: true,
      })
    );
    await flushPromises();
    expect(document.activeElement.dataset.date).toBe('2030-01-16');

    document.activeElement.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'ArrowRight',
        bubbles: true,
        cancelable: true,
      })
    );
    await flushPromises();
    expect(document.activeElement.dataset.date).toBe('2030-01-15');
  } finally {
    wrapper.unmount();
    app.remove();
  }
});
