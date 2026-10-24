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
    await flushPromises();
    const menu = wrapper.getComponent(DropdownMenu);
    expect(dialog.contains(menu.element)).toBe(true);
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

it.each([
  {
    top: 500,
    bottom: 520,
    footerTop: 600,
    windowHeight: 844,
    above: true,
    maxHeight: 320,
  },
  {
    top: 100,
    bottom: 120,
    footerTop: 600,
    windowHeight: 844,
    above: false,
    maxHeight: 320,
  },
  {
    top: 100,
    bottom: 120,
    footerTop: 260,
    windowHeight: 844,
    above: false,
    maxHeight: 132,
  },
  {
    top: 200,
    bottom: 220,
    footerTop: 300,
    windowHeight: 400,
    above: true,
    maxHeight: 176,
  },
])(
  'keeps the caret and footer clear with available height: %j',
  async ({ top, bottom, footerTop, windowHeight, above, maxHeight }) => {
    const form = document.createElement('form');
    const editor = document.createElement('div');
    const footer = document.createElement('footer');
    form.append(editor, footer);
    document.body.append(form);
    vi.spyOn(footer, 'getBoundingClientRect').mockReturnValue({
      top: footerTop,
    });
    vi.stubGlobal('innerHeight', windowHeight);
    vi.stubGlobal('innerWidth', 390);
    const wrapper = mount(ToolsDropdown, {
      attachTo: editor,
      props: { items: tools },
    });
    const range = {
      collapse: vi.fn(),
      getBoundingClientRect: () => ({ top, bottom, left: 380 }),
    };
    const selection = vi.spyOn(window, 'getSelection').mockReturnValue({
      rangeCount: 1,
      anchorNode: wrapper.get('span').element,
      getRangeAt: () => ({ cloneRange: () => range }),
    });
    try {
      document.dispatchEvent(new Event('selectionchange'));
      await flushPromises();
      const menu = wrapper.getComponent(DropdownMenu);
      const floating = menu.element.parentElement;
      expect(floating.style.left).toBe('1rem');
      expect(floating.style[above ? 'bottom' : 'top']).toBe(
        above
          ? `${(windowHeight - top + 8) / 16}rem`
          : `${(bottom + 8) / 16}rem`
      );
      expect(parseFloat(menu.element.style.maxHeight)).toBeLessThanOrEqual(
        maxHeight
      );
      expect(wrapper.vm.placement.maxHeight).toBe(maxHeight);
      // A scroll moves the stored DOM range even when keyboard focus is in the menu.
      range.getBoundingClientRect = () => ({
        top: top - 20,
        bottom: bottom - 20,
        left: 20,
      });
      selection.mockReturnValue({ rangeCount: 0 });
      window.dispatchEvent(new Event('scroll'));
      await flushPromises();
      expect(wrapper.vm.caret.top).toBe(top - 20);
    } finally {
      wrapper.unmount();
      form.remove();
      vi.restoreAllMocks();
      vi.unstubAllGlobals();
    }
  }
);
