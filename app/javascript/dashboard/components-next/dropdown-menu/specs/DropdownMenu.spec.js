import { mount } from '@vue/test-utils';
import { h } from 'vue';
import DropdownMenu from '../DropdownMenu.vue';

const items = [
  { value: 'first', label: 'First', action: 'choose', isSelected: true },
  { value: 'second', label: 'Second', action: 'choose' },
];

describe('DropdownMenu optional picker behavior', () => {
  it('preserves default action-menu styles, local filtering and action payloads', async () => {
    const wrapper = mount(DropdownMenu, {
      props: { menuItems: items, showSearch: true },
    });
    try {
      expect(wrapper.classes()).toContain('absolute');
      expect(wrapper.classes()).toContain('rounded-xl');
      expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
      expect(wrapper.find('[role="option"]').exists()).toBe(false);
      await wrapper.get('input').setValue('second');
      expect(wrapper.findAll('button')).toHaveLength(1);
      expect(wrapper.emitted('search').at(-1)).toEqual(['second']);
      await wrapper.get('button').trigger('click');
      expect(wrapper.emitted('action').at(-1)).toEqual([items[1]]);
    } finally {
      wrapper.unmount();
    }
  });

  it('keeps section separators by default and makes suppression opt-in', async () => {
    const wrapper = mount(DropdownMenu, {
      props: {
        menuSections: [
          { title: 'One', items: items.slice(0, 1) },
          { title: 'Two', items: items.slice(1) },
        ],
      },
      slots: { footer: () => h('button', 'Footer') },
    });
    try {
      expect(wrapper.findAll('.h-px')).toHaveLength(1);
      expect(wrapper.get('p').classes()).toContain('sticky');
      await wrapper.setProps({ showSectionDividers: false, compact: true });
      expect(wrapper.findAll('.h-px')).toHaveLength(0);
      expect(wrapper.classes()).toContain('rounded-lg');
      expect(wrapper.text()).toContain('Footer');
    } finally {
      wrapper.unmount();
    }
  });

  it('supports controlled search, portal positioning, listbox selection and optional focus', async () => {
    const wrapper = mount(DropdownMenu, {
      props: {
        menuItems: items,
        portal: true,
        listbox: true,
        multiple: true,
        showSearch: true,
        searchValue: 'first',
        autoFocus: false,
      },
      attachTo: document.body,
    });
    try {
      expect(wrapper.classes()).toContain('fixed');
      expect(wrapper.classes()).not.toContain('absolute');
      expect(
        wrapper.get('[role="listbox"]').attributes('aria-multiselectable')
      ).toBe('true');
      expect(wrapper.get('[role="option"]').attributes('aria-selected')).toBe(
        'true'
      );
      wrapper.vm.focus();
      expect(document.activeElement).toBe(wrapper.get('input').element);
      await wrapper.get('[role="option"]').trigger('keydown', { key: 'Enter' });
      expect(wrapper.emitted('action').at(-1)).toEqual([items[0]]);
      await wrapper.setProps({ searchValue: '' });
      expect(wrapper.get('input').element.value).toBe('');
      expect(wrapper.findAll('[role="option"]')).toHaveLength(2);
      await wrapper.setProps({
        menuItems: [],
        emptyState: 'Custom empty text',
      });
      expect(wrapper.text()).toContain('Custom empty text');
    } finally {
      wrapper.unmount();
    }
  });
});
