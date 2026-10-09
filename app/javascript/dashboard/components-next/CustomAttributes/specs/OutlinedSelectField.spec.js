import { mount, flushPromises } from '@vue/test-utils';
import { toRaw } from 'vue';
import OutlinedSelectField from '../OutlinedSelectField.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

describe('OutlinedSelectField', () => {
  it('portals the shared menu and emits the original option, including numeric zero', async () => {
    const options = [
      { id: 0, name: 'None' },
      { id: 7, name: 'Ana' },
    ];
    const wrapper = mount(OutlinedSelectField, {
      props: { label: 'Agent', options, selectedItem: options[1] },
      attachTo: document.body,
    });
    await wrapper.get('button').trigger('click');
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.element.parentElement).toBe(document.body);
    expect(menu.classes()).toContain('fixed');
    expect(menu.get('button:last-child .i-lucide-check').exists()).toBe(true);
    await menu.get('button').trigger('click');
    expect(toRaw(wrapper.emitted('select')[0][0])).toBe(options[0]);
    await flushPromises();
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('button').element);
    wrapper.unmount();
  });

  it('keeps a disabled field closed', async () => {
    const wrapper = mount(OutlinedSelectField, {
      props: { label: 'Agent', disabled: true },
    });
    await wrapper.get('button').trigger('click');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    wrapper.unmount();
  });
});
