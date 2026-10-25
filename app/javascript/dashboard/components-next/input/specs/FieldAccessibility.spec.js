import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import Input from '../Input.vue';
import DurationInput from '../DurationInput.vue';
import ComboBox from '../../combobox/ComboBox.vue';
import DateField from '../../date-field/DateField.vue';
import components from 'dashboard/i18n/locale/en/components.json';

it.each([Input, ComboBox, DateField])(
  'associates the label, help and complete error with the real control in %s',
  component => {
    const wrapper = mount(component, {
      props: {
        id: 'field',
        label: 'Field',
        help: 'Instructions',
        message: 'First line\nSecond line',
        messageType: 'error',
        hasError: true,
        options: [],
      },
      attrs: { 'aria-describedby': 'external' },
    });
    const control = wrapper.get('label').element.control;
    expect(control).toBe(wrapper.get('#field').element);
    expect(['INPUT', 'BUTTON']).toContain(control.tagName);
    expect(control.getAttribute('aria-invalid')).toBe('true');
    expect(control.getAttribute('aria-describedby')).toBe(
      'external field-help field-message'
    );
    expect(wrapper.get('#field-help').text()).toBe('Instructions');
    expect(wrapper.get('[role="alert"]').element.textContent).toContain(
      'First line\nSecond line'
    );
    expect(wrapper.get('[role="alert"]').classes()).not.toContain('truncate');
    expect(wrapper.findAll('[role="alert"]')).toHaveLength(1);
    wrapper.unmount();
  }
);

it.each([
  ['text', '007', '007'],
  ['number', '7', 7],
  ['number', '', ''],
])('preserves Input %s value type for %s', async (type, typed, expected) => {
  const wrapper = mount(Input, { props: { type } });
  await wrapper.get('input').setValue(typed);
  expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([expected]);
  wrapper.unmount();
});

it('completes a duration with keyboard and preserves numeric minutes and string units', async () => {
  const wrapper = mount(DurationInput, {
    attachTo: document.body,
    props: { customUnitSelect: true, modelValue: 60 },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: components },
        }),
      ],
    },
  });
  expect(wrapper.get('input').attributes('aria-label')).toBe('Enter duration');
  await wrapper.get('input').setValue('90');
  await wrapper.get('input').trigger('keydown', { key: 'Enter' });
  expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([90]);
  const trigger = wrapper.get('button');
  expect(trigger.attributes('aria-label')).toBe('Duration unit');
  await trigger.trigger('keydown', { key: 'ArrowDown' });
  await flushPromises();
  const searchOrMenu = document.activeElement;
  searchOrMenu.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true })
  );
  await flushPromises();
  expect(document.activeElement.getAttribute('role')).toBe('option');
  document.activeElement.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true })
  );
  await flushPromises();
  document.activeElement.click();
  await flushPromises();
  expect(wrapper.emitted('update:unit').at(-1)).toEqual(['hours']);
  await trigger.trigger('keydown', { key: 'ArrowDown' });
  await flushPromises();
  const event = new KeyboardEvent('keydown', {
    key: 'Tab',
    bubbles: true,
    cancelable: true,
  });
  document.activeElement.dispatchEvent(event);
  await flushPromises();
  expect(event.defaultPrevented).toBe(false);
  expect(trigger.attributes('aria-expanded')).toBe('false');
  wrapper.unmount();
});

it('shows a slow, rejected and retried remote search without changing the query or selected ID', async () => {
  let resolveSearch;
  let rejectSearch;
  const request = vi.fn(
    () =>
      new Promise((resolve, reject) => {
        resolveSearch = resolve;
        rejectSearch = reject;
      })
  );
  const Host = defineComponent({
    components: { ComboBox },
    setup() {
      const selected = ref(7);
      const loading = ref(false);
      const failed = ref(false);
      const search = async query => {
        loading.value = true;
        failed.value = false;
        try {
          await request(query);
        } catch {
          failed.value = true;
        } finally {
          loading.value = false;
        }
      };
      return { selected, loading, failed, search };
    },
    template:
      '<ComboBox v-model="selected" :options="[{value:7,label:`Selected`}]" use-api-results :loading="loading" :search-error="failed" @search="search" />',
  });
  const wrapper = mount(Host);
  await wrapper.get('button').trigger('click');
  const input = wrapper.get('input[type="search"]');
  await input.setValue('customer');
  expect(wrapper.get('[aria-busy="true"]').exists()).toBe(true);
  expect(wrapper.get('[role="status"]').text()).toBe('COMBOBOX.SEARCHING');
  rejectSearch(new Error('offline'));
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe('COMBOBOX.SEARCH_ERROR');
  expect(input.element.value).toBe('customer');
  expect(wrapper.vm.selected).toBe(7);
  expect(request).toHaveBeenCalledTimes(1);
  const retry = wrapper
    .findAll('button')
    .find(button => button.text() === 'COMBOBOX.RETRY');
  await retry.trigger('click');
  expect(request).toHaveBeenLastCalledWith('customer');
  expect(request).toHaveBeenCalledTimes(2);
  resolveSearch();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.vm.selected).toBe(7);
  expect(wrapper.get('input').element.value).toBe('customer');
  wrapper.unmount();
});

it('keeps container selectors and forwards accessible attributes and events only to the input', async () => {
  const wrapper = mount(Input, {
    attrs: {
      'data-testid': 'field',
      'aria-label': 'Name',
      'aria-describedby': 'help',
    },
  });
  expect(wrapper.attributes('data-testid')).toBe('field');
  expect(wrapper.attributes('aria-label')).toBeUndefined();
  expect(wrapper.findAll('[aria-label="Name"]')).toHaveLength(1);
  expect(wrapper.get('input').attributes('aria-describedby')).toBe('help');
  await wrapper.get('input').trigger('keydown', { key: 'Enter' });
  expect(wrapper.emitted('keydown')).toHaveLength(1);
  await wrapper.setProps({ message: 'Error', messageType: 'error' });
  expect(wrapper.get('input').attributes('aria-describedby')).toContain(
    'help input-'
  );
  wrapper.unmount();
});
