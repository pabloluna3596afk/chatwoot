import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Draggable from 'vuedraggable';
import ContactColumnMenu from '../ContactColumnMenu.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const { settings, persist } = vi.hoisted(() => ({
  settings: {},
  persist: vi.fn(),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => settings,
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: () => [] }),
}));

describe('ContactColumnMenu', () => {
  it('preserves column toggling and ordering inside the shared panel and disables reordering during search', async () => {
    Object.assign(settings, {
      uiSettings: ref({
        contacts_table_columns: ['name', 'email', 'phone_number', 'identifier'],
      }),
      updateUISettings: persist,
    });
    const wrapper = mount(ContactColumnMenu);
    await wrapper.get('button').trigger('click');
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.props('portal')).toBe(true);
    const checkbox = menu.findAll('input[type="checkbox"]')[1];
    await checkbox.setValue(false);
    expect(persist.mock.calls.at(-1)[0].contacts_table_columns).toEqual([
      'name',
      'phone_number',
      'identifier',
    ]);
    const draggable = wrapper.getComponent(Draggable);
    const order = [...draggable.props('modelValue')].reverse();
    draggable.vm.$emit('update:modelValue', order);
    draggable.vm.$emit('end');
    expect(persist.mock.calls.at(-1)[0].contacts_table_columns).toEqual([
      'name',
      'identifier',
      'phone_number',
    ]);
    await menu.get('input[type="search"]').setValue('email');
    expect(draggable.vm.$attrs.disabled).toBe(true);
    expect(menu.findAll('input[type="checkbox"]')).toHaveLength(1);
    wrapper.unmount();
  });
});
