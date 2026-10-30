import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { describe, expect, it } from 'vitest';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ToolCategoryPicker from './ToolCategoryPicker.vue';

describe('ToolCategoryPicker', () => {
  it('resolves case, accent and whitespace variants to the existing category', async () => {
    const wrapper = mount(ToolCategoryPicker, {
      props: { categories: ['Ventas'] },
    });
    wrapper.findComponent(ComboBox).vm.$emit('search', '  veNtaS ');
    expect(wrapper.emitted('update:modelValue')).toEqual([['Ventas']]);
  });

  it('creates a trimmed category and clears the selection', async () => {
    const wrapper = mount(ToolCategoryPicker, {
      props: { categories: [] },
    });
    await wrapper.findComponent(ComboBox).get('button').trigger('click');
    wrapper.findComponent(ComboBox).vm.$emit('search', '  Atención   VIP ');
    await nextTick();
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(wrapper.emitted('create')).toEqual([['Atención VIP']]);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      'Atención VIP',
    ]);
    await wrapper.setProps({ modelValue: 'Atención VIP' });
    await wrapper.findAll('button').at(-1).trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
  });

  it('suggests matching names and disables creation of normalized duplicates', async () => {
    const wrapper = mount(ToolCategoryPicker, {
      props: { categories: ['Ventas', 'Atención VIP'] },
    });
    const comboBox = wrapper.findComponent(ComboBox);
    await comboBox.get('button').trigger('click');
    comboBox.vm.$emit('search', 'atencion');
    await nextTick();
    expect(comboBox.props('options')).toEqual([
      { value: 'Atención VIP', label: 'Atención VIP' },
    ]);
    comboBox.vm.$emit('search', '  VENTAS  ');
    await nextTick();
    expect(
      wrapper.findAll('button').at(-1).attributes('disabled')
    ).toBeDefined();
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['Ventas']);
  });
});
