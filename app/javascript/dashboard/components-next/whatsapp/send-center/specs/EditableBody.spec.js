import { mount, flushPromises } from '@vue/test-utils';
import EditableBody from '../EditableBody.vue';

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
    const fields = wrapper.findAll('input');
    expect(fields.map(field => field.attributes('aria-invalid'))).toEqual([
      'false',
      'false',
    ]);
    expect(fields[0].attributes('placeholder')).toBe('Customer name');
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
    await wrapper.get('input').trigger('blur');
    expect(wrapper.get('input').attributes('aria-invalid')).toBe('true');
    await wrapper.setProps({ text: 'New template {{name}}' });
    await flushPromises();
    expect(wrapper.get('input').attributes('aria-invalid')).toBe('false');
    wrapper.unmount();
  });
});
