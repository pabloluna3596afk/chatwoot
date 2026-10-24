import { shallowMount, flushPromises } from '@vue/test-utils';
import TaskDetail from '../TaskDetail.vue';
import TaskDetailHeader from '../TaskDetailHeader.vue';
import TaskReassignPanel from '../TaskReassignPanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 3 } }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../TaskDetailConversation.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../ConversationTaskForm.vue', () => ({
  default: { template: '<div />' },
}));

describe('mobile task detail', () => {
  it('loads the URL task, refreshes after editing and returns within the account', async () => {
    const dispatch = vi.fn().mockResolvedValue();
    const wrapper = shallowMount(TaskDetail, {
      props: { taskId: '42', isOnExpandedLayout: true },
      global: {
        stubs: { WootTabs: true, WootTabsItem: true },
        config: {
          globalProperties: {
            $store: {
              dispatch,
              getters: {
                'internalTasks/getUIFlags': {},
                'internalTasks/getSelectedTask': {
                  id: 42,
                  title: 'Task',
                  events: [],
                },
              },
            },
          },
        },
      },
    });
    expect(dispatch).toHaveBeenCalledWith('internalTasks/fetchTask', {
      taskId: '42',
    });
    wrapper.findComponent(TaskDetailHeader).vm.$emit('updated');
    await flushPromises();
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(dispatch).toHaveBeenCalledTimes(2);
    wrapper.findComponent(Button).vm.$emit('click');
    expect(push).toHaveBeenCalledWith({ path: '/app/accounts/3/tasks' });
    await wrapper.setProps({ taskId: '43' });
    expect(dispatch).toHaveBeenLastCalledWith('internalTasks/fetchTask', {
      taskId: '43',
    });
    wrapper.unmount();
  });

  it('saves the existing assignment payload before announcing an update', async () => {
    let finishSave;
    const saving = new Promise(resolve => {
      finishSave = resolve;
    });
    const dispatch = vi.fn(type =>
      type === 'internalTasks/updateTask' ? saving : Promise.resolve()
    );
    const wrapper = shallowMount(TaskReassignPanel, {
      props: {
        task: { id: 42, conversation: { id: 8 }, assignedToId: 5 },
        embedded: true,
      },
      global: {
        config: {
          globalProperties: {
            $store: {
              dispatch,
              getters: {
                'internalTasks/getUIFlags': {},
                'teams/getTeams': [{ id: 7, name: 'Sales' }],
                'agents/getAgents': [{ id: 5, name: 'Agent' }],
              },
            },
          },
        },
      },
    });
    wrapper
      .findAllComponents({ name: 'OutlinedSelectField' })[0]
      .vm.$emit('select', { id: 7 });
    wrapper.findAllComponents(Button)[1].vm.$emit('click');
    expect(dispatch).toHaveBeenLastCalledWith('internalTasks/updateTask', {
      taskId: 42,
      conversationId: 8,
      payload: { assigned_to_id: null, team_id: 7 },
    });
    expect(wrapper.emitted('updated')).toBeUndefined();
    finishSave();
    await flushPromises();
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
});
