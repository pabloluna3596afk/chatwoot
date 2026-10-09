import { mount, flushPromises } from '@vue/test-utils';
import AttributeCategoryInput from '../AttributeCategoryInput.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

it('keeps free category text and uses the real menu for suggestions with keyboard focus', async () => {
  const wrapper = mount(AttributeCategoryInput, {
    attachTo: document.body,
    props: {
      options: ['Ventas', 'Soporte'],
      label: 'Category',
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
  });
  try {
    const input = wrapper.get('input');
    input.element.focus();
    await input.setValue('Ve');
    await flushPromises();
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.element.parentElement).toBe(document.body);
    expect(menu.findAll('button')).toHaveLength(1);
    await input.trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(menu.get('button').element);
    await menu.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.props('modelValue')).toBe('Ventas');
    expect(document.activeElement).toBe(input.element);
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    await input.setValue('New arbitrary category');
    await flushPromises();
    expect(wrapper.props('modelValue')).toBe('New arbitrary category');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    await input.setValue('');
    await input.trigger('keydown', { key: 'ArrowDown' });
    await wrapper
      .getComponent(DropdownMenu)
      .trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(document.activeElement).toBe(input.element);
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});
