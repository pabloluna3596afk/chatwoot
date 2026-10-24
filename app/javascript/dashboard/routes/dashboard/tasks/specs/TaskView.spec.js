import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { routes } from '../routes';
import TaskList from 'dashboard/components-next/InternalTasks/TaskList.vue';
import TaskKanban from 'dashboard/components-next/InternalTasks/TaskKanban.vue';
import TaskDetail from 'dashboard/components-next/InternalTasks/TaskDetail.vue';
import TaskListTeamFilter from 'dashboard/components-next/InternalTasks/TaskListTeamFilter.vue';
import TaskListStatusFilter from 'dashboard/components-next/InternalTasks/TaskListStatusFilter.vue';
import ChatTypeTabs from 'dashboard/components/widgets/ChatTypeTabs.vue';
import InternalTasksAPI from 'dashboard/api/internalTasks';

vi.mock('dashboard/components-next/InternalTasks/TaskDetail.vue', () => ({
  default: {
    props: ['taskId', 'isOnExpandedLayout'],
    emits: ['updated'],
    template: '<div />',
  },
}));

const viewport = ref(390);
vi.mock('@vueuse/core', async original => ({
  ...(await original()),
  useWindowSize: () => ({ width: viewport }),
}));

vi.mock('dashboard/api/internalTasks', () => ({
  default: { getTasks: vi.fn() },
}));

describe('task workspace panels', () => {
  let wrapper;
  let router;
  let dispatch;

  beforeEach(() => {
    InternalTasksAPI.getTasks.mockResolvedValue({ data: [] });
    dispatch = vi.fn().mockResolvedValue();
    viewport.value = 390;
  });

  afterEach(() => wrapper?.unmount());

  it.each([390, 1280])(
    'opens a direct URL at %i without fetching the hidden board',
    async width => {
      viewport.value = width;
      router = createRouter({
        history: createMemoryHistory(),
        routes,
      });
      await router.push('/app/accounts/3/tasks/42');
      wrapper = mount(RouterView, {
        attachTo: document.body,
        global: {
          plugins: [router],
          config: {
            globalProperties: {
              $store: {
                dispatch,
                getters: {
                  'internalTasks/getUIFlags': {},
                  'internalTasks/getAccountTasks': [],
                  'internalTasks/getTabCounts': {},
                },
              },
            },
          },
          stubs: {
            TaskDetail: true,
            TaskListTeamFilter: true,
            TaskListStatusFilter: true,
            ChatTypeTabs: true,
          },
        },
      });
      await flushPromises();
      expect(wrapper.findComponent(TaskDetail).props()).toMatchObject({
        taskId: '42',
        isOnExpandedLayout: width < 768,
      });
      expect(wrapper.findComponent(TaskList).find('h1').exists()).toBe(
        width >= 768
      );
      expect(wrapper.findComponent(TaskKanban).isVisible()).toBe(false);
      expect(InternalTasksAPI.getTasks).not.toHaveBeenCalled();
      wrapper.findComponent(TaskDetail).vm.$emit('updated');
      await flushPromises();
      expect(InternalTasksAPI.getTasks).not.toHaveBeenCalled();
      await router.push('/app/accounts/3/tasks');
      await flushPromises();
      expect(wrapper.findComponent(TaskList).find('h1').exists()).toBe(true);
      expect(wrapper.findComponent(TaskDetail).exists()).toBe(false);
      expect(InternalTasksAPI.getTasks).toHaveBeenCalledTimes(
        width < 768 ? 0 : 1
      );
    }
  );

  it('keeps list and board filters through selection, updates and viewport changes', async () => {
    router = createRouter({
      history: createMemoryHistory(),
      routes,
    });
    await router.push('/app/accounts/3/tasks');
    wrapper = mount(RouterView, {
      attachTo: document.body,
      global: {
        plugins: [router],
        config: {
          globalProperties: {
            $store: {
              dispatch,
              getters: {
                'internalTasks/getUIFlags': {},
                'internalTasks/getAccountTasks': [],
                'internalTasks/getTabCounts': {},
              },
            },
          },
        },
        stubs: {
          TaskDetail: true,
          TaskListTeamFilter: true,
          TaskListStatusFilter: true,
          ChatTypeTabs: true,
        },
      },
    });
    await flushPromises();
    const list = wrapper.findComponent(TaskList);
    const board = wrapper.findComponent(TaskKanban);
    expect(InternalTasksAPI.getTasks).not.toHaveBeenCalled();
    expect(wrapper.findAll('button')[0].attributes('aria-pressed')).toBe(
      'true'
    );
    expect(wrapper.findAll('button')[0].classes()).toContain('bg-n-slate-9/10');
    expect(wrapper.findAll('button')[1].attributes('aria-pressed')).toBe(
      'false'
    );
    list.findComponent(TaskListTeamFilter).vm.$emit('update:modelValue', 7);
    list
      .findComponent(TaskListStatusFilter)
      .vm.$emit('update:modelValue', 'completed');
    list.findComponent(ChatTypeTabs).vm.$emit('chatTabChange', 'all');
    await flushPromises();
    await wrapper.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(board.isVisible()).toBe(true);
    expect(InternalTasksAPI.getTasks).toHaveBeenCalledTimes(1);
    expect(wrapper.findAll('button')[0].attributes('aria-pressed')).toBe(
      'false'
    );
    expect(wrapper.findAll('button')[0].classes()).not.toContain(
      'bg-n-slate-9/10'
    );
    expect(wrapper.findAll('button')[1].attributes('aria-pressed')).toBe(
      'true'
    );
    expect(wrapper.findAll('button')[1].classes()).toContain('bg-n-slate-9/10');
    board.findComponent(TaskListTeamFilter).vm.$emit('update:modelValue', 9);
    await flushPromises();
    await router.push('/app/accounts/3/tasks/42');
    await flushPromises();
    const callsBeforeUpdate = InternalTasksAPI.getTasks.mock.calls.length;
    wrapper.findComponent(TaskDetail).vm.$emit('updated');
    await flushPromises();
    expect(InternalTasksAPI.getTasks).toHaveBeenCalledTimes(callsBeforeUpdate);
    await router.push('/app/accounts/3/tasks');
    await flushPromises();
    expect(board.isVisible()).toBe(true);
    expect(InternalTasksAPI.getTasks).toHaveBeenCalledTimes(
      callsBeforeUpdate + 1
    );
    expect(InternalTasksAPI.getTasks).toHaveBeenLastCalledWith(
      expect.objectContaining({ team_id: 9 })
    );
    await wrapper.findAll('button')[0].trigger('click');
    expect(list.findComponent(TaskListTeamFilter).props('modelValue')).toBe(7);
    expect(list.findComponent(TaskListStatusFilter).props('modelValue')).toBe(
      'completed'
    );
    expect(list.findComponent(ChatTypeTabs).props('activeTab')).toBe('all');
    viewport.value = 1280;
    await flushPromises();
    expect(list.props('showTaskList')).toBe(true);
    expect(list.props('isOnExpandedLayout')).toBe(false);
    expect(board.isVisible()).toBe(true);
    await router.push('/app/accounts/3/tasks/42');
    await flushPromises();
    expect(list.find('h1').exists()).toBe(true);
    expect(wrapper.findComponent(TaskDetail).props('isOnExpandedLayout')).toBe(
      false
    );
    expect(wrapper.findComponent(TaskKanban).isVisible()).toBe(false);
  });
});
