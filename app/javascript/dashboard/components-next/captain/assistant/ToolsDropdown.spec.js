import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ToolsDropdown from './ToolsDropdown.vue';
import TagTools from 'dashboard/components/widgets/conversation/TagTools.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const tools = [
  { id: 'first', title: 'First tool', description: 'First description' },
  { id: 'second', title: 'Second tool', description: 'Second description' },
];
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref(tools),
}));
vi.mock('dashboard/composables/useKeyboardNavigableList', () => ({
  useKeyboardNavigableList: vi.fn(),
}));

it('portals tools inside the native dialog, preserves editor focus and closes on Escape', async () => {
  const dialog = document.createElement('dialog');
  document.body.appendChild(dialog);
  const wrapper = mount(ToolsDropdown, {
    props: { items: tools },
    global: { provide: { dialogPortalTarget: ref(dialog) } },
  });
  try {
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.element.parentElement).toBe(dialog);
    expect(menu.classes()).toContain('fixed');
    expect(menu.get('button').attributes('type')).toBe('button');
    const event = new MouseEvent('mousedown', {
      cancelable: true,
      bubbles: true,
    });
    menu.get('button').element.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    await menu.get('button').trigger('click');
    expect(wrapper.emitted('select')).toEqual([[0]]);
    await menu.trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.emitted('close')).toHaveLength(1);
  } finally {
    wrapper.unmount();
    dialog.remove();
  }
});

it('navigates focused tool buttons without submitting the surrounding form', async () => {
  const wrapper = mount(ToolsDropdown, {
    props: { items: tools, selectedIndex: 0 },
  });
  try {
    const menu = wrapper.getComponent(DropdownMenu);
    await menu.get('button').trigger('keydown', { key: 'End' });
    expect(wrapper.emitted('update:selectedIndex')).toEqual([[1]]);
    await menu.findAll('button')[1].trigger('click');
    expect(wrapper.emitted('select')).toEqual([[1]]);
  } finally {
    wrapper.unmount();
  }
});

it('selects index zero after navigating to another tool and retains the tool object', async () => {
  const wrapper = mount(TagTools);
  try {
    wrapper.vm.selectedIndex = 1;
    wrapper.vm.onSelect(0);
    expect(wrapper.emitted('selectTool')).toEqual([[tools[0]]]);
    await wrapper.setProps({ searchKey: 'second' });
    await flushPromises();
    wrapper.vm.onSelect();
    expect(wrapper.emitted('selectTool').at(-1)).toEqual([tools[1]]);
  } finally {
    wrapper.unmount();
  }
});
