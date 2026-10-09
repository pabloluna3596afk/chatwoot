import { mount, flushPromises } from '@vue/test-utils';
import ListAttribute from '../ListAttribute.vue';
import CustomAttribute from 'dashboard/components/CustomAttribute.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

describe('list attributes', () => {
  it('uses the shared floating menu and ends focus state after selecting', async () => {
    const wrapper = mount(ListAttribute, {
      props: {
        attribute: {
          attributeDisplayName: 'Plan',
          attributeValues: ['Basic', 'Pro'],
          value: 'Basic',
        },
      },
    });
    await wrapper.get('button').trigger('click');
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.props('portal')).toBe(true);
    await menu.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(wrapper.emitted('update')).toEqual([['Pro']]);
    expect(wrapper.emitted('focusChange')).toEqual([[true], [false]]);
    wrapper.unmount();
  });

  it('keeps the older attribute update payload and does not allow editing a read-only attribute', async () => {
    const wrapper = mount(CustomAttribute, {
      props: {
        label: 'Plan',
        attributeKey: 'plan',
        attributeType: 'list',
        value: 'Basic',
        values: ['Basic', 'Pro'],
      },
    });
    await wrapper.get('button').trigger('click');
    await wrapper
      .getComponent(DropdownMenu)
      .findAll('button')[1]
      .trigger('click');
    expect(wrapper.emitted('update')[0]).toEqual(['plan', 'Pro']);
    await wrapper.setProps({ readOnly: true });
    await wrapper.get('button').trigger('click');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
    wrapper.unmount();
  });
});
