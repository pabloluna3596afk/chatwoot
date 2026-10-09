import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ConversationAssigneeSelector from '../ConversationAssigneeSelector.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const { state, assign, selfAssign } = vi.hoisted(() => ({
  state: {},
  assign: vi.fn(),
  selfAssign: vi.fn(),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getSelectedChat: {} }, dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/useConversationAssignee', () => ({
  useConversationAssignee: () => state,
}));
vi.mock('dashboard/composables/useCaptainState', () => ({
  useCaptainState: () => ({
    showAssistantAvatar: false,
    assistant: {},
    ringClass: '',
  }),
}));

describe('ConversationAssigneeSelector', () => {
  it('distinguishes human and Captain identities with the same id and keeps the self assignment action', async () => {
    const human = { id: 7, name: 'Ana', assignee_type: 'User' };
    const captain = {
      id: 7,
      name: 'Captain',
      assignee_type: 'Captain::Assistant',
    };
    Object.assign(state, {
      agentsList: ref([human, captain]),
      assignedAgent: ref(captain),
      showSelfAssign: ref(true),
      isAssigning: ref(false),
      onClickAssignAgent: assign,
      onSelfAssign: selfAssign,
    });
    const wrapper = mount(ConversationAssigneeSelector, {
      attachTo: document.body,
      props: { showSelfAssignButton: true },
      global: { mocks: { $t: key => key }, directives: { tooltip: {} } },
    });
    await wrapper.get('button').trigger('click');
    expect(wrapper.getComponent(MenuPopover).props('open')).toBe(true);
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.props('menuItems').map(item => item.isSelected)).toEqual([
      false,
      true,
    ]);
    expect(new Set(menu.props('menuItems').map(item => item.value)).size).toBe(
      2
    );
    await menu.findAll('button')[0].trigger('click');
    expect(assign).toHaveBeenCalledWith(human);
    await wrapper.get('button').trigger('click');
    await wrapper
      .getComponent(DropdownMenu)
      .findAll('button')
      .at(-1)
      .trigger('click');
    expect(selfAssign).toHaveBeenCalled();
    wrapper.unmount();
  });
});
