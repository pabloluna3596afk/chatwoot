import { mount } from '@vue/test-utils';
import FlowFooter from '../FlowFooter.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
const captain = vi.hoisted(() => ({ options: [] }));
vi.mock('dashboard/composables/useCaptainAssignment', () => ({
  useCaptainAssignment: () => ({
    options: {
      get value() {
        return captain.options;
      },
    },
  }),
}));

describe('FlowFooter', () => {
  beforeEach(() => {
    captain.options = [];
  });

  it('offers Captain exit mode and persists an optional named assistant', async () => {
    captain.options = [
      { id: 'captain', name: 'General' },
      { id: 'captain:7', name: 'Captain · Ventas' },
    ];
    const exitPolicy = Object.fromEntries(
      ['on_complete', 'on_handoff', 'on_fail', 'on_human_break'].map(key => [
        key,
        { status: 'open', assignee_mode: 'none' },
      ])
    );
    const wrapper = mount(FlowFooter, { props: { exitPolicy } });
    const modePicker = wrapper.findAllComponents(ComboBox)[1];
    expect(modePicker.props('options')).toContainEqual({
      value: 'captain',
      label: 'CAPTAIN.ASSIGNMENT.MODE',
    });
    await modePicker.vm.$emit('update:modelValue', 'captain');
    const pickers = wrapper.findAllComponents(ComboBox);
    expect(pickers[0].props('disabled')).toBe(true);
    expect(pickers[2].props('options')).toEqual([
      { value: null, label: 'General' },
      { value: 7, label: 'Captain · Ventas' },
    ]);
    await pickers[2].vm.$emit('update:modelValue', 7);
    expect(exitPolicy.on_complete).toMatchObject({
      assignee_mode: 'captain',
      assistant_id: 7,
    });
    wrapper.unmount();
  });

  it('keeps a deleted assistant visible on a saved Captain exit policy', () => {
    const exitPolicy = Object.fromEntries(
      ['on_complete', 'on_handoff', 'on_fail', 'on_human_break'].map(key => [
        key,
        { status: 'open', assignee_mode: 'captain', assistant_id: 99 },
      ])
    );
    const wrapper = mount(FlowFooter, { props: { exitPolicy } });
    expect(
      wrapper.findAllComponents(ComboBox)[2].props('options')
    ).toContainEqual({ value: 99, label: 'CAPTAIN.ASSIGNMENT.DELETED' });
    wrapper.unmount();
  });
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
