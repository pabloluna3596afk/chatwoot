import { mount, flushPromises } from '@vue/test-utils';
import ListCard from './ListCard.vue';
import DropdownMenu from '../dropdown-menu/DropdownMenu.vue';
import MenuPopover from '../dropdown-menu/MenuPopover.vue';

describe('ListCard', () => {
  it('keeps full identity available and renders all slots', () => {
    const wrapper = mount(ListCard, {
      props: { title: 'A long name', subtitle: 'long@example.com' },
      slots: { avatar: 'Avatar', chips: 'Role', after: 'Details' },
    });
    expect(wrapper.get('h3').attributes('title')).toBe('A long name');
    expect(wrapper.get('p').attributes('title')).toBe('long@example.com');
    expect(wrapper.text()).toContain('Avatar');
    expect(wrapper.get('[data-list-chips]').text()).toBe('Role');
    expect(wrapper.text()).toContain('Details');
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('provides a 44px trigger and emits selection through the real menu', async () => {
    const wrapper = mount(ListCard, {
      attachTo: document.body,
      props: {
        title: 'Ana',
        menuItems: [
          { action: 'edit', value: 42, label: 'Edit', disabled: true },
          { action: 'delete', value: 42, label: 'Delete' },
        ],
      },
    });
    const trigger = wrapper.get('button');
    expect(wrapper.getComponent(MenuPopover).props('side')).toBe('bottom');
    expect(trigger.classes()).toEqual(
      expect.arrayContaining(['size-11', 'min-h-11', 'min-w-11'])
    );
    expect(trigger.attributes('aria-label')).toContain('Ana');
    await trigger.trigger('click');
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.classes()).toContain('!bg-n-solid-3');
    expect(menu.findAll('button')[0].attributes('disabled')).toBeDefined();
    await menu.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(wrapper.emitted('action')[0][0]).toMatchObject({
      action: 'delete',
      value: 42,
    });
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
    wrapper.unmount();
  });
});
