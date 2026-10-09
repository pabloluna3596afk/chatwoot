import { mount } from '@vue/test-utils';
import FlowFooter from '../FlowFooter.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

describe('FlowFooter', () => {
  it('keeps nullable team ids and status values when selecting through the real floating menu', async () => {
    const exitPolicy = Object.fromEntries(
      ['on_complete', 'on_handoff', 'on_fail', 'on_human_break'].map(key => [
        key,
        {
          status: 'open',
          assignee_mode: 'team',
          team_id: null,
        },
      ])
    );
    const wrapper = mount(FlowFooter, {
      props: { exitPolicy, teams: [{ id: 7, name: 'Sales' }] },
      attachTo: document.body,
    });
    const pickers = wrapper.findAllComponents(ComboBox);
    await pickers[2].get('button').trigger('click');
    const menu = pickers[2].getComponent(DropdownMenu);
    expect(menu.element.parentElement).toBe(document.body);
    await menu.findAll('button')[1].trigger('click');
    expect(exitPolicy.on_complete.team_id).toBe(7);
    await pickers[2].get('button').trigger('click');
    await pickers[2].getComponent(DropdownMenu).get('button').trigger('click');
    expect(exitPolicy.on_complete.team_id).toBeNull();
    await pickers[0].get('button').trigger('click');
    await pickers[0]
      .getComponent(DropdownMenu)
      .findAll('button')[2]
      .trigger('click');
    expect(exitPolicy.on_complete.status).toBe('resolved');
    wrapper.unmount();
  });
});
