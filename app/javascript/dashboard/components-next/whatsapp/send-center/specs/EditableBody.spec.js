import { mount, flushPromises } from '@vue/test-utils';
import EditableBody from '../EditableBody.vue';
import { withFullI18n } from 'test-i18n';
withFullI18n('en');

vi.mock('dashboard/components-next/variable-picker/VariablePicker.vue', () => ({
  default: { template: '<button type="button">{ }</button>' },
}));

describe('inline template fields', () => {
  it('shows ruby immediately and marks invalid only after attempting send', async () => {
    const wrapper = mount(EditableBody, {
      props: {
        text: 'Hello {{name}}, order {{order}}',
        labelFor: key =>
          ({ name: 'Customer name', order: 'Order number' })[key],
        invalidKeys: ['name', 'order'],
      },
    });
    await flushPromises();
    const fields = wrapper.findAll('textarea');
    expect(fields.map(field => field.attributes('aria-invalid'))).toEqual([
      'false',
      'false',
    ]);
    expect(fields[0].attributes('placeholder')).toBe('Type the value');
    await fields[0].trigger('blur');
    expect(fields[0].attributes('aria-invalid')).toBe('false');
    expect(
      fields[0].element.parentElement.classList.contains('bg-n-ruby-3')
    ).toBe(true);
    expect(fields[1].attributes('aria-invalid')).toBe('false');
    await wrapper.setProps({ attempted: true });
    expect(fields[1].attributes('aria-invalid')).toBe('true');
    expect(
      fields[1].element.parentElement.classList.contains('border-n-ruby-9')
    ).toBe(true);
    await wrapper.setProps({ values: { name: 'Ana' }, invalidKeys: ['order'] });
    expect(fields[0].attributes('aria-invalid')).toBe('false');
    wrapper.unmount();
  });

  it('resets touched fields when template text changes', async () => {
    const wrapper = mount(EditableBody, {
      props: { text: '{{name}}', labelFor: key => key, invalidKeys: ['name'] },
    });
    await flushPromises();
    await wrapper.get('textarea').trigger('blur');
    expect(wrapper.get('textarea').attributes('aria-invalid')).toBe('false');
    await wrapper.setProps({ text: 'New template {{name}}' });
    await flushPromises();
    expect(wrapper.get('textarea').attributes('aria-invalid')).toBe('false');
    wrapper.unmount();
  });
});

describe('inline field keyboard and values', () => {
  it('keeps IME input pending and advances only on a committed Enter', async () => {
    const wrapper = mount(EditableBody, {
      props: { text: '{{1}}', labelFor: key => key },
    });
    await flushPromises();
    const field = wrapper.get('textarea');
    await field.trigger('compositionstart');
    field.element.value = '\u4f60\u597d';
    await field.trigger('input');
    await field.trigger('keydown', { key: 'Enter', isComposing: true });
    expect(wrapper.emitted('change')).toBeUndefined();
    expect(wrapper.emitted('advance')).toBeUndefined();
    await field.trigger('compositionend');
    expect(wrapper.emitted('change')).toEqual([['1', '\u4f60\u597d']]);
    await field.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('advance')).toEqual([[field.element]]);
    wrapper.unmount();
  });

  it('shows the resolved contact value and preserves the expression on selection', async () => {
    const wrapper = mount(EditableBody, {
      props: {
        text: '{{1}}',
        labelFor: key => key,
        values: { 1: 'Ana' },
        expressions: { 1: '{{contact.name}}' },
        systemVariables: [
          {
            id: 'name',
            expression: '{{contact.name}}',
            label: 'Contact name',
            value: 'Ana',
            disabled: false,
          },
        ],
      },
    });
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('Ana');
    expect(wrapper.get('textarea').attributes('title')).toBe(
      'Contact name · {{1}}'
    );
    await wrapper.get('textarea').trigger('focus');
    expect(wrapper.emitted('hint').at(-1)).toEqual([
      'Detail 1 of 1 · Contact name · {{1}}',
    ]);
    expect(wrapper.get('textarea').attributes('readonly')).toBeDefined();
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('change')).toEqual([['1', '']]);
    wrapper.unmount();
  });
});

describe('field help and variable keyboard access', () => {
  it('updates help on focus, keeps it while tabbing to the picker, and clears it on exit', async () => {
    const wrapper = mount(EditableBody, {
      attachTo: document.body,
      props: {
        text: '{{name}} / {{order}}',
        labelFor: key => key,
        examples: { name: 'Alex' },
      },
    });
    await flushPromises();
    const fields = wrapper.findAll('textarea');
    fields[0].element.focus();
    await flushPromises();
    expect(wrapper.emitted('hint').at(-1)).toEqual([
      'Detail 1 of 2 · {{name}} · E.g.: Alex',
    ]);
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    await fields[0].trigger('click');
    expect(wrapper.get('[role=listbox]').exists()).toBe(true);
    fields[1].element.focus();
    await flushPromises();
    expect(wrapper.emitted('hint').at(-1)).toEqual([
      'Detail 2 of 2 · {{order}}',
    ]);
    expect(wrapper.find('[role=listbox]').exists()).toBe(false);
    fields[1].element.blur();
    await flushPromises();
    expect(wrapper.emitted('hint').at(-1)).toEqual(['']);
    expect(wrapper.emitted('change')).toBeUndefined();
    expect(wrapper.find('[role="tooltip"]').exists()).toBe(false);
    wrapper.unmount();
  });
});

describe('safe variable and template text', () => {
  it.each([
    '<script>alert(1)</script>',
    '<img src=x onerror=alert(1)>',
    '&lt;',
  ])('renders source and values literally: %s', value => {
    const wrapper = mount(EditableBody, {
      props: {
        text: `${value} *{{1}}*`,
        values: { 1: value },
        labelFor: key => key,
      },
    });
    expect(wrapper.find('script,img').exists()).toBe(false);
    expect(wrapper.element.textContent).toContain(value);
    expect(wrapper.get('textarea').element.value).toBe(value);
    expect(wrapper.findAll('strong')).toHaveLength(1);
    wrapper.unmount();
  });
});

it.each(['1', 'nombre_y_apellido'])(
  'keeps the exact Meta variable %s in the title and keyboard help',
  async key => {
    const wrapper = mount(EditableBody, {
      props: { text: `Hola {{${key}}}`, labelFor: () => 'Customer name' },
    });
    await flushPromises();
    const field = wrapper.get('textarea');
    expect(field.attributes('title')).toBe(`{{${key}}}`);
    expect(field.attributes('placeholder')).toBe('Type the value');
    await field.trigger('focus');
    expect(wrapper.emitted('hint').at(-1)).toEqual([
      `Detail 1 of 1 · {{${key}}}`,
    ]);
    await wrapper.setProps({ values: { [key]: 'Ana' } });
    expect(field.attributes('title')).toBe(`{{${key}}}`);
    wrapper.unmount();
  }
);
