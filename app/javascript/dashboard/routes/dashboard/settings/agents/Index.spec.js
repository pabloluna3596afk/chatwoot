import { mount } from '@vue/test-utils';
import Index from './Index.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('./AddAgent.vue', () => ({
  default: { name: 'AddAgent', template: '<div />' },
}));
vi.mock('./EditAgent.vue', () => ({
  default: { name: 'EditAgent', props: ['id'], template: '<div />' },
}));
vi.mock('dashboard/components-next/page/PageLayout.vue', () => ({
  default: {
    name: 'PageLayout',
    template:
      '<div><slot name="title"/><slot name="moreInfo"/><slot name="toolbar"/><slot/></div>',
  },
}));

const agents = [
  {
    id: 1,
    name: 'Self',
    email: 'self@test.co',
    role: 'agent',
    confirmed: true,
    availability_status: 'online',
  },
  {
    id: 2,
    name: 'Admin',
    email: 'admin@test.co',
    role: 'administrator',
    confirmed: true,
    availability_status: 'busy',
  },
  {
    id: 3,
    name: 'Pending',
    email: 'pending@test.co',
    role: 'administrator',
    confirmed: false,
    availability_status: 'offline',
  },
  {
    id: 4,
    name: 'Custom',
    email: 'custom@test.co',
    role: 'agent',
    confirmed: true,
    custom_role_id: 9,
    availability_status: 'online',
  },
];

describe('Agents ListCard integration', () => {
  it('preserves permissions, roles, status, search and existing edit/delete dialogs', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = mount(Index, {
      global: {
        renderStubDefaultSlot: true,
        plugins: [
          app => {
            app.config.globalProperties.$store = {
              dispatch,
              getters: {
                'agents/getAgents': agents,
                'agents/getUIFlags': {},
                getCurrentUserID: 1,
                'customRole/getCustomRoles': [
                  {
                    id: 9,
                    name: 'Support',
                    permissions: ['conversation_manage'],
                  },
                ],
              },
            };
          },
        ],
        stubs: {
          CustomBrandPolicyWrapper: { template: '<div><slot /></div>' },
          WootLoadingState: { template: '<div />' },
          ListCard: {
            ...ListCard,
            template: '<div><slot name="avatar"/><slot name="chips"/></div>',
          },
          Avatar: { template: '<div><slot name="badge"/></div>' },
          WootModal: { template: '<div><slot/></div>' },
          WootDeleteModal: {
            name: 'WootDeleteModal',
            props: ['show', 'onConfirm'],
            template: '<button @click="onConfirm">Confirm</button>',
          },
        },
      },
    });
    let cards = wrapper.findAllComponents(ListCard);
    expect(cards[0].props('menuItems')).toEqual([]);
    expect(cards[1].props('menuItems').map(item => item.action)).toEqual([
      'edit',
    ]);
    expect(cards[2].props('menuItems').map(item => item.action)).toEqual([
      'edit',
      'delete',
    ]);
    expect(cards[3].text()).toContain('Support');
    expect(cards[3].get('span.truncate').attributes('title')).toContain(
      'CUSTOM_ROLE.PERMISSIONS.CONVERSATION_MANAGE'
    );
    expect(
      wrapper.findAll('[data-agent-availability]').map(dot => dot.classes())
    ).toEqual([
      expect.arrayContaining(['bg-n-teal-10', 'ring-2']),
      expect.arrayContaining(['bg-n-amber-10', 'ring-2']),
      expect.arrayContaining(['bg-n-slate-9', 'ring-2']),
      expect.arrayContaining(['bg-n-teal-10', 'ring-2']),
    ]);
    await cards[3].vm.$emit('action', { action: 'edit' });
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent({ name: 'EditAgent' }).props('id')).toBe(4);
    await cards[2].vm.$emit('action', { action: 'delete' });
    await wrapper.vm.$nextTick();
    const dialog = wrapper.getComponent({ name: 'WootDeleteModal' });
    expect(dialog.props('show')).toBe(true);
    expect(dispatch).not.toHaveBeenCalledWith(
      'agents/delete',
      expect.anything()
    );
    dispatch.mockReturnValue(new Promise(() => {}));
    await dialog.trigger('click');
    expect(dispatch).toHaveBeenCalledWith('agents/delete', 3);
    expect(cards[2].props('title')).toBe('Pending');
    expect(cards[2].props('menuItems').every(item => item.disabled)).toBe(true);
    await wrapper
      .getComponent(SearchInput)
      .vm.$emit('update:modelValue', 'custom@test.co');
    await wrapper.vm.$nextTick();
    cards = wrapper.findAllComponents(ListCard);
    expect(cards).toHaveLength(1);
    expect(cards[0].props('title')).toBe('Custom');
    wrapper.unmount();
  });
});
