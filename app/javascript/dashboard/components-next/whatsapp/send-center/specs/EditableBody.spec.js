import { mount, flushPromises } from '@vue/test-utils';
import EditableBody from '../EditableBody.vue';
import { withFullI18n } from 'test-i18n';
withFullI18n('en');

vi.mock('dashboard/components-next/variable-picker/VariablePicker.vue', () => ({
  default: { template: '<span />' },
}));

describe('inline template fields', () => {
  it('shows errors only after leaving a missing field or attempting send', async () => {
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
    expect(fields[0].attributes('placeholder')).toBe('Data 1');
    await fields[0].trigger('blur');
    expect(fields[0].attributes('aria-invalid')).toBe('true');
    expect(fields[1].attributes('aria-invalid')).toBe('false');
    await wrapper.setProps({ attempted: true });
    expect(fields[1].attributes('aria-invalid')).toBe('true');
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
    expect(wrapper.get('textarea').attributes('aria-invalid')).toBe('true');
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
      },
    });
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('Ana');
    expect(wrapper.get('textarea').attributes('title')).toBe(
      '{{contact.name}}'
    );
    expect(wrapper.find('.bg-n-teal-9').exists()).toBe(true);
    wrapper.unmount();
  });
});
