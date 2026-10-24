import { mount, flushPromises } from '@vue/test-utils';
import TaskDetailHeader from '../TaskDetailHeader.vue';
import TaskReassignPanel from '../TaskReassignPanel.vue';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 3 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('task reassignment with real select portals', () => {
  let wrapper;

  afterEach(() => wrapper?.unmount());

  it.each([
    [0, 'Sales', { assigned_to_id: null, team_id: 7 }],
    [1, 'Ana', { assigned_to_id: 6, team_id: null }],
  ])(
    'keeps the panel open after selecting field %i until save resolves',
    async (field, name, payload) => {
      let finishSave;
      const saving = new Promise(resolve => {
        finishSave = resolve;
      });
      const dispatch = vi.fn(type =>
        type === 'internalTasks/updateTask' ? saving : Promise.resolve()
      );
      wrapper = mount(TaskDetailHeader, {
        attachTo: document.body,
        props: {
          task: {
            id: 42,
            title: 'Follow up',
            status: 'pending',
            assignedToId: 5,
          },
        },
        global: {
          stubs: { RouterLink: true },
          config: {
            globalProperties: {
              $store: {
                dispatch,
                getters: {
                  'internalTasks/getUIFlags': {},
                  'teams/getTeams': [{ id: 7, name: 'Sales' }],
                  'agents/getAgents': [{ id: 6, name: 'Ana' }],
                },
              },
            },
          },
        },
      });
      const toggle = wrapper
        .findAllComponents(Button)
        .find(
          button => button.props('label') === 'INTERNAL_TASKS.REASSIGN.TOGGLE'
        );
      await toggle.trigger('click');
      expect(wrapper.findComponent(TaskReassignPanel).exists()).toBe(true);
      const panel = wrapper.getComponent(TaskReassignPanel);
      const select = panel.findAllComponents(OutlinedSelectField)[field];
      await select.get('button').trigger('click');
      await flushPromises();
      // VueUse suppresses multiple clicks in one event-loop turn.
      await new Promise(resolve => {
        setTimeout(resolve, 0);
      });
      const option = select
        .getComponent(DropdownMenu)
        .findAll('button')
        .find(row => row.text().includes(name));
      // Dispatch the native pointer/click sequence so the parent's outside listener runs.
      option.element.dispatchEvent(
        new MouseEvent('pointerdown', { bubbles: true, composed: true })
      );
      option.element.focus();
      option.element.click();
      await flushPromises();
      expect(wrapper.findComponent(TaskReassignPanel).exists()).toBe(true);
      expect(select.get('button').text()).toContain(name);
      expect(document.activeElement).toBe(select.get('button').element);
      expect(wrapper.emitted('updated')).toBeUndefined();
      await panel.findAllComponents(Button)[1].trigger('click');
      expect(dispatch).toHaveBeenLastCalledWith('internalTasks/updateTask', {
        taskId: 42,
        conversationId: undefined,
        payload,
      });
      expect(wrapper.findComponent(TaskReassignPanel).exists()).toBe(true);
      finishSave();
      await flushPromises();
      expect(wrapper.emitted('updated')).toHaveLength(1);
      expect(wrapper.findComponent(TaskReassignPanel).exists()).toBe(false);
      // A real outside click still dismisses the panel.
      await toggle.trigger('click');
      await flushPromises();
      document.body.dispatchEvent(
        new MouseEvent('pointerdown', { bubbles: true })
      );
      document.body.click();
      await flushPromises();
      expect(wrapper.findComponent(TaskReassignPanel).exists()).toBe(false);
    }
  );
});
