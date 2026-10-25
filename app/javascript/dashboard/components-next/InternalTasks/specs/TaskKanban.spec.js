import { flushPromises, mount } from '@vue/test-utils';
import TaskKanban from '../TaskKanban.vue';
import InternalTasksAPI from 'dashboard/api/internalTasks';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/api/internalTasks', () => ({
  default: { getTasks: vi.fn() },
}));

const tasks = [
  {
    id: 42,
    title: 'Follow up',
    status: 'open',
    description: '',
    due_at: null,
    assigned_to: null,
    team: { id: 7, name: 'Sales' },
    conversation: { id: 9, contact: { name: 'Customer' } },
  },
];

const mountBoard = () =>
  mount(TaskKanban, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        TaskListTeamFilter: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<button data-testid="team" @click="$emit(\'update:modelValue\', 7)">Team</button>',
        },
        TaskKanbanCard: {
          props: ['task'],
          template: '<article>{{ task.title }}</article>',
        },
        Spinner: true,
      },
    },
  });

describe('TaskKanban load errors', () => {
  beforeEach(() => {
    InternalTasksAPI.getTasks.mockReset();
  });

  it('shows a retry block after a failed initial load and recovers', async () => {
    InternalTasksAPI.getTasks
      .mockRejectedValueOnce(new Error('Network unavailable'))
      .mockResolvedValueOnce({ data: tasks });
    const wrapper = mountBoard();
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Network unavailable'
    );
    expect(wrapper.find('article').exists()).toBe(false);
    await wrapper.get('[role="alert"] button').trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.get('article').text()).toBe('Follow up');
    expect(InternalTasksAPI.getTasks).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('keeps cards and selected team after refresh failure and retries with the same filters', async () => {
    InternalTasksAPI.getTasks
      .mockResolvedValueOnce({ data: tasks })
      .mockResolvedValueOnce({ data: tasks });
    const wrapper = mountBoard();
    await flushPromises();
    await wrapper.get('[data-testid="team"]').trigger('click');
    await flushPromises();
    InternalTasksAPI.getTasks
      .mockRejectedValueOnce(new Error('Refresh failed'))
      .mockResolvedValueOnce({ data: tasks });
    await wrapper.vm.refresh();
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain('Refresh failed');
    expect(wrapper.get('[role="alert"]').classes()).toContain('bg-n-ruby-3');
    expect(wrapper.get('article').text()).toBe('Follow up');
    const failedRequest = InternalTasksAPI.getTasks.mock.calls[2][0];
    await wrapper.get('[role="alert"] button').trigger('click');
    await flushPromises();
    expect(InternalTasksAPI.getTasks.mock.calls[3][0]).toEqual(failedRequest);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('hides the loading skeleton from assistive technology while the first request is pending', async () => {
    let resolve;
    InternalTasksAPI.getTasks.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mountBoard();
    await flushPromises();
    const skeleton = wrapper.get('[aria-hidden="true"][inert]');
    expect(skeleton.exists()).toBe(true);
    expect(wrapper.get('[aria-busy="true"]').exists()).toBe(true);
    resolve({ data: tasks });
    await flushPromises();
    wrapper.unmount();
  });
});
