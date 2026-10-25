import { mount } from '@vue/test-utils';
import Checkbox from '../Checkbox.vue';

describe('Checkbox', () => {
  it('keeps a native wrapping label associated with the real input', () => {
    const wrapper = mount(
      {
        components: { Checkbox },
        template: '<label>Choose item <Checkbox /></label>',
      },
      { attachTo: document.body }
    );

    expect(wrapper.get('label').element.control).toBe(
      wrapper.get('input').element
    );
    wrapper.unmount();
  });

  it('forwards accessible attributes to the real input', () => {
    const wrapper = mount(Checkbox, {
      attrs: { id: 'select-item', 'aria-label': 'Select item', name: 'item' },
    });
    const input = wrapper.get('input');

    expect(input.attributes('id')).toBe('select-item');
    expect(input.attributes('aria-label')).toBe('Select item');
    expect(input.attributes('name')).toBe('item');
    expect(input.classes()).toContain('focus-visible:ring-2');
    expect(input.classes()).toContain('max-sm:h-11');
    expect(input.classes()).toContain('max-sm:w-11');
    expect(input.classes()).toContain('ltr:-translate-x-1/2');
    expect(input.classes()).toContain('rtl:translate-x-1/2');
  });

  it('preserves v-model, indeterminate, disabled and change behavior', async () => {
    const wrapper = mount(Checkbox, { props: { indeterminate: true } });
    const input = wrapper.get('input');
    expect(input.element.indeterminate).toBe(true);

    await input.setValue(true);
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([true]);
    expect(wrapper.emitted('change')).toHaveLength(1);

    await wrapper.setProps({ disabled: true });
    expect(input.attributes('disabled')).toBeDefined();
  });
});
