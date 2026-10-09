import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import MenuPopover from '../MenuPopover.vue';
import DropdownMenu from '../DropdownMenu.vue';

describe('MenuPopover', () => {
  it('keeps the menu in the native dialog top layer when a dialog provides its portal', () => {
    const dialog = document.createElement('dialog');
    document.body.appendChild(dialog);
    const wrapper = mount(MenuPopover, {
      props: { open: true, menuItems: [{ label: 'All', value: 'all' }] },
      global: { provide: { dialogPortalTarget: ref(dialog) } },
    });
    try {
      expect(wrapper.getComponent(DropdownMenu).element.parentElement).toBe(
        dialog
      );
    } finally {
      wrapper.unmount();
      dialog.remove();
    }
  });

  it('portals the real menu, skips disabled actions and restores focus on Escape and selection', async () => {
    const wrapper = mount(MenuPopover, {
      attachTo: document.body,
      props: {
        menuItems: [
          {
            label: 'Blocked',
            action: 'blocked',
            disabled: true,
            title: 'Save first',
          },
          { label: 'JSON', action: 'json', testId: 'json-action' },
          { label: 'Test', action: 'test' },
        ],
      },
      slots: { trigger: '<button @click="params.toggle">Actions</button>' },
    });
    try {
      const trigger = wrapper.get('button');
      trigger.element.focus();
      await trigger.trigger('keydown', { key: 'ArrowDown' });
      const menu = wrapper.getComponent(DropdownMenu);
      expect(menu.element.parentElement).toBe(document.body);
      expect(menu.classes()).toContain('fixed');
      expect(Number(menu.element.style.zIndex)).toBeGreaterThan(10000);
      expect(menu.props('showSectionDividers')).toBe(false);
      expect(menu.get('button').attributes('title')).toBe('Save first');
      expect(document.activeElement).toBe(
        menu.get('[data-testid="json-action"]').element
      );
      await menu
        .get('[data-testid="json-action"]')
        .trigger('keydown', { key: 'End' });
      expect(document.activeElement.textContent).toBe('Test');
      await menu.trigger('keydown', { key: 'Escape' });
      await flushPromises();
      expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
      expect(document.activeElement).toBe(trigger.element);
      await trigger.trigger('click');
      await wrapper
        .getComponent(DropdownMenu)
        .get('[data-testid="json-action"]')
        .trigger('click');
      await flushPromises();
      expect(wrapper.emitted('action')[0][0].action).toBe('json');
      expect(document.activeElement).toBe(trigger.element);
    } finally {
      wrapper.unmount();
    }
  });

  it('keeps search focus inside the portal and supports composed content without an empty-state row', async () => {
    const wrapper = mount(MenuPopover, {
      attachTo: document.body,
      props: {
        showSearch: true,
        menuItems: [{ label: 'Language', value: 'es' }],
      },
      slots: { trigger: '<button @click="params.toggle">Open</button>' },
    });
    try {
      wrapper.get('button').element.focus();
      await wrapper.get('button').trigger('click');
      await flushPromises();
      const menu = wrapper.getComponent(DropdownMenu);
      expect(document.activeElement).toBe(menu.get('input').element);
      await menu.get('input').setValue('Lang');
      expect(wrapper.emitted('search').at(-1)).toEqual(['Lang']);
      await menu.trigger('keydown', { key: 'Escape' });
    } finally {
      wrapper.unmount();
    }
    const composed = mount(MenuPopover, {
      props: { open: true },
      slots: { content: '<p data-testid="status">Published</p>' },
    });
    try {
      const menu = composed.getComponent(DropdownMenu);
      expect(menu.get('[data-testid="status"]').text()).toBe('Published');
      expect(menu.text()).not.toContain('EMPTY_STATE');
    } finally {
      composed.unmount();
    }
  });
});
