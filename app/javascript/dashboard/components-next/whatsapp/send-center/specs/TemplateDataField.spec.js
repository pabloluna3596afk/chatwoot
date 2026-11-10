import { mount, flushPromises } from '@vue/test-utils';
import TemplateDataField from '../TemplateDataField.vue';
import { withFullI18n } from 'test-i18n';

withFullI18n('en');
const options = [
  {
    id: 'name',
    label: 'Contact name',
    value: 'Alex',
    expression: '{{ contact.name }}',
    disabled: false,
  },
  {
    id: 'phone',
    label: 'Phone',
    value: '',
    expression: '{{ contact.phone }}',
    disabled: true,
  },
  {
    id: 'email',
    label: 'Email',
    value: 'alex@example.com',
    expression: '{{ contact.email }}',
    disabled: false,
  },
];

describe('free text and system variable combobox', () => {
  it('filters without taking focus and confirms plain text on Enter, Tab and blur', async () => {
    const wrapper = mount(TemplateDataField, {
      attachTo: document.body,
      props: { label: 'Detail 1 of 1', options },
    });
    const input = wrapper.get('textarea');
    input.element.focus();
    await flushPromises();
    expect(input.attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    await input.trigger('click');
    expect(wrapper.findAll('[role=option]')).toHaveLength(3);
    expect(wrapper.get('[aria-disabled=true]').attributes('title')).toBe(
      'No data'
    );
    await input.setValue('*Alex*');
    expect(wrapper.get('[role=option]').text()).toBe('Use “*Alex*”');
    expect(document.activeElement).toBe(input.element);
    await input.trigger('keydown', { key: 'Enter' });
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    expect(wrapper.emitted('change')).toEqual([['*Alex*']]);
    expect(wrapper.emitted('select')).toBeUndefined();
    await input.trigger('focus');
    await input.setValue('Phone');
    await input.trigger('keydown', { key: 'Tab' });
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    await input.trigger('focus');
    input.element.blur();
    await flushPromises();
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('uses arrows and Enter to choose enabled variables, with a resolved removable chip', async () => {
    const wrapper = mount(TemplateDataField, {
      props: { label: 'Detail', options },
    });
    const input = wrapper.get('textarea');
    await input.trigger('focus');
    await input.trigger('click');
    await wrapper.get('[aria-disabled=true]').trigger('click');
    expect(wrapper.emitted('select')).toBeUndefined();
    await input.trigger('keydown', { key: 'ArrowDown' });
    expect(input.attributes('aria-activedescendant')).toBe(
      wrapper.get('[aria-selected=true]').attributes('id')
    );
    await input.trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.get('[aria-selected=true]').text()).toContain('Email');
    await input.trigger('keydown', { key: 'ArrowUp' });
    await input.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('select')).toEqual([['{{ contact.name }}']]);
    await wrapper.setProps({
      expression: '{{ contact.name }}',
      value: '{{ contact.name }}',
    });
    expect(input.element.value).toBe('Alex');
    expect(input.attributes('title')).toBe('Contact name');
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('change')).toEqual([['']]);
  });

  it('chooses by click and Escape closes without changing the value', async () => {
    const wrapper = mount(TemplateDataField, {
      props: { label: 'Detail', options },
    });
    const input = wrapper.get('textarea');
    await input.trigger('focus');
    await input.trigger('click');
    await input.trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    expect(wrapper.emitted('change')).toBeUndefined();
    await input.trigger('focus');
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('click');
    await wrapper.findAll('[role=option]')[2].trigger('click');
    expect(wrapper.emitted('select')).toEqual([['{{ contact.email }}']]);
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('focus');
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
  });

  it('keeps Tab focus closed and opens with ArrowDown or filtered typing', async () => {
    const wrapper = mount(TemplateDataField, {
      attachTo: document.body,
      props: { label: 'Detail', options },
    });
    const input = wrapper.get('textarea');
    input.element.focus();
    await flushPromises();
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    await input.trigger('keydown', { key: 'ArrowUp' });
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('keydown', { key: 'ArrowDown' });
    expect(input.attributes('aria-expanded')).toBe('true');
    await input.trigger('keydown', { key: 'Tab' });
    input.element.blur();
    input.element.focus();
    await flushPromises();
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.setValue('Email');
    expect(input.attributes('aria-expanded')).toBe('true');
    expect(wrapper.findAll('[role=option]')).toHaveLength(2);
    expect(wrapper.findAll('[role=option]')[1].text()).toContain('Email');
    await wrapper.get('[role=option]').trigger('click');
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('focus');
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('keydown', { key: 'Enter' });
    expect(input.attributes('aria-expanded')).toBe('false');
    await input.trigger('click');
    expect(input.attributes('aria-expanded')).toBe('true');
    wrapper.unmount();
  });
});
