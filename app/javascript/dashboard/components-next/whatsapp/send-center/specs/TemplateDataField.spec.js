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

  it('uses arrows and Enter to choose enabled variables, with an editable resolved value', async () => {
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
    expect(wrapper.get('[aria-selected=true]').text()).toContain(
      'alex@example.com'
    );
    await input.trigger('keydown', { key: 'ArrowUp' });
    await input.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('select')).toEqual([['{{ contact.name }}']]);
    await wrapper.setProps({
      expression: '{{ contact.name }}',
      value: '{{ contact.name }}',
    });
    expect(input.element.value).toBe('Alex');
    expect(input.attributes('title')).toBe('Contact name');
    await input.trigger('click');
    await wrapper.findAll('[role=option]').at(-1).trigger('click');
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
    expect(wrapper.findAll('[role=option]')[1].text()).toContain(
      'alex@example.com'
    );
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

describe('field examples and pending state', () => {
  it('keeps the full example available while editing and clearing a value', async () => {
    const wrapper = mount(TemplateDataField, {
      props: { label: 'Date', placeholder: '12 de noviembre', missing: true },
    });
    const input = wrapper.get('textarea');
    expect(input.attributes('placeholder')).toBe('12 de noviembre');
    expect(input.attributes('aria-invalid')).toBe('false');
    expect(wrapper.classes()).toContain('bg-n-ruby-3');
    await wrapper.setProps({ value: '12', missing: false });
    expect(input.element.value).toBe('12');
    expect(input.attributes('placeholder')).toBe('12 de noviembre');
    expect(wrapper.classes()).not.toContain('bg-n-ruby-3');
    expect(wrapper.classes()).toContain('bg-n-brand/10');
    expect(wrapper.classes()).toContain('border-n-brand/30');
    await input.setValue('');
    expect(wrapper.emitted('change')).toEqual([['']]);
    await wrapper.setProps({ value: '', missing: true, attempted: true });
    expect(input.attributes('aria-invalid')).toBe('true');
    expect(wrapper.classes()).toContain('border-n-ruby-9');
    expect(wrapper.classes()).toContain('bg-n-ruby-3');
    wrapper.unmount();
  });
});

describe('ChatHub field presentation', () => {
  it('shows the example until a default resolves, then the actual value in blue', async () => {
    const expression = '{{ contact.name }}';
    const wrapper = mount(TemplateDataField, {
      props: {
        label: 'Detail 1 of 1',
        value: expression,
        expression,
        placeholder: 'Alex Example',
        status: 'loading',
      },
    });
    const input = wrapper.get('textarea');
    expect(input.element.value).toBe('');
    expect(input.attributes('placeholder')).toBe('Alex Example');
    expect(wrapper.text()).not.toContain(expression);
    expect(wrapper.classes()).toContain('bg-n-ruby-3');
    await wrapper.setProps({ value: 'Alex', options, status: 'ready' });
    expect(input.element.value).toBe('Alex');
    expect(input.attributes('title')).toBe('Contact name');
    expect(wrapper.classes()).toContain('bg-n-brand/10');
    expect(wrapper.classes()).toContain('border-n-brand/30');
    expect(wrapper.text()).not.toContain('Contact name');
    expect(wrapper.text()).not.toContain(expression);
    expect(wrapper.emitted('change')).toBeUndefined();
    wrapper.unmount();
  });

  it('opens the system menu from the field without a picker button and searches resolved options', async () => {
    const wrapper = mount(TemplateDataField, {
      props: { label: 'Detail', options },
    });
    expect(wrapper.find('button').exists()).toBe(false);
    await wrapper.get('textarea').trigger('click');
    const search = wrapper.get('input[type=search]');
    expect(search.attributes('placeholder')).toBe('Search or type\u2026');
    await search.setValue('alex@example');
    expect(wrapper.findAll('[role=option]')).toHaveLength(2);
    await search.trigger('keydown', { key: 'ArrowDown' });
    await search.trigger('keydown', { key: 'ArrowDown' });
    await search.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('select')).toEqual([['{{ contact.email }}']]);
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    wrapper.unmount();
  });
});

it('anchors the field menu inside a narrow bubble', async () => {
  const bubble = document.createElement('div');
  bubble.dataset.testid = 'editable-body';
  document.body.appendChild(bubble);
  const wrapper = mount(TemplateDataField, {
    attachTo: bubble,
    props: { label: 'Detail', options },
  });
  document.documentElement.style.fontSize = '16px';
  bubble.getBoundingClientRect = () => ({ left: 100, right: 450 });
  wrapper.element.getBoundingClientRect = () => ({ left: 100, right: 250 });
  await wrapper.get('textarea').trigger('click');
  expect(
    wrapper.get('[role=listbox]').element.parentElement.classList
  ).toContain('start-0');
  wrapper.unmount();
  bubble.remove();
  document.documentElement.style.removeProperty('font-size');
});

it('sizes to the actual value without reserving a remove button column', async () => {
  const wrapper = mount(TemplateDataField, {
    props: { label: 'Detail', placeholder: 'Type the value', options },
  });
  expect(wrapper.get('[aria-hidden=true]').text()).toBe('Type the value');
  await wrapper.setProps({ value: 'A' });
  expect(wrapper.get('[aria-hidden=true]').text()).toBe('A');
  await wrapper.setProps({ expression: '{{ contact.name }}' });
  expect(wrapper.get('textarea').element.value).toBe('Alex');
  expect(wrapper.find('button').exists()).toBe(false);
  await wrapper.get('textarea').trigger('click');
  expect(wrapper.findAll('[role=option]').map(row => row.text())).toEqual([
    'Alex',
    'No data',
    'alex@example.com',
    'Remove',
  ]);
  await wrapper.findAll('[role=option]').at(-1).trigger('click');
  expect(wrapper.emitted('change')).toEqual([['']]);
  wrapper.unmount();
});

it('shows actual values only, including long values, and accepts custom search text', async () => {
  const value = 'A very long contact name that must remain completely readable';
  const wrapper = mount(TemplateDataField, {
    props: {
      label: 'Detail',
      options: [
        ...options,
        {
          id: 'long',
          label: 'Technical label',
          value,
          expression: '{{contact.long}}',
        },
      ],
    },
  });
  await wrapper.get('textarea').trigger('click');
  const rows = wrapper.findAll('[role=option]');
  expect(rows.map(row => row.text())).toEqual([
    'Alex',
    'No data',
    'alex@example.com',
    value,
  ]);
  expect(wrapper.text()).not.toContain('Contact name');
  expect(wrapper.text()).not.toContain('Technical label');
  expect(wrapper.text()).not.toContain('System variables');
  const search = wrapper.get('input[type=search]');
  await search.setValue('Custom text');
  expect(wrapper.get('[role=option]').text()).toBe(
    'Use \u201cCustom text\u201d'
  );
  await search.trigger('keydown', { key: 'Enter' });
  expect(wrapper.emitted('change')).toEqual([['Custom text']]);
  expect(wrapper.emitted('select')).toBeUndefined();
  wrapper.unmount();
});
