import { defineComponent, computed, reactive, ref } from 'vue';
import { mount } from '@vue/test-utils';
import AutomationActionInput from '../AutomationActionInput.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import useAutomationValues from 'dashboard/composables/useAutomationValues';
import { useMacros } from 'dashboard/composables/useMacros';
import actionQueryGenerator from 'dashboard/helper/actionQueryGenerator';

const { state, dispatch } = vi.hoisted(() => ({
  state: {},
  dispatch: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: key => computed(() => state[key]),
  useStoreGetters: () =>
    Object.fromEntries(
      Object.keys(state).map(key => [key, computed(() => state[key])])
    ),
}));

const Host = defineComponent({
  components: { AutomationActionInput },
  props: {
    inboxIds: { type: Array, default: () => [] },
    macro: Boolean,
    selected: { type: String, default: 'captain' },
  },
  setup(props) {
    const { getActionDropdownValues } = useAutomationValues();
    const { getMacroDropdownValues } = useMacros();
    const options = computed(() =>
      (props.macro ? getMacroDropdownValues : getActionDropdownValues)(
        'assign_agent',
        props.inboxIds
      )
    );
    const action = ref({
      action_name: 'assign_agent',
      action_params: [{ id: props.selected, name: 'saved' }],
    });
    return {
      action,
      options,
      types: [
        {
          key: 'assign_agent',
          label: 'Assign agent',
          inputType: 'search_select',
        },
      ],
    };
  },
  template:
    '<AutomationActionInput v-model="action" :action-types="types" :dropdown-values="options" />',
});

describe('Captain in the shared action editor', () => {
  it('updates options with pinned inboxes while retaining a now unavailable selection', async () => {
    const wrapper = mount(Host, {
      props: { inboxIds: [1], selected: 'captain:7' },
    });
    const select = wrapper.findAllComponents(SingleSelect)[1];
    expect(select.props('options')[0]).toMatchObject({
      id: 'captain:7',
      name: 'Ventas',
    });
    await wrapper.setProps({ inboxIds: [2] });
    expect(select.props('options')[0]).toMatchObject({
      id: 'captain',
      description: 'CAPTAIN.ASSIGNMENT.NO_ASSISTANT',
    });
    expect(select.props('options')).toContainEqual(
      expect.objectContaining({
        id: 'captain:7',
        description: 'CAPTAIN.ASSIGNMENT.UNAVAILABLE',
      })
    );
    expect(actionQueryGenerator([wrapper.vm.action])[0].action_params).toEqual([
      'captain:7',
    ]);
    wrapper.unmount();
  });

  beforeEach(() => {
    Object.assign(
      state,
      reactive({
        'accounts/isFeatureEnabledonAccount': () => true,
        'captainAssistants/getRecords': [{ id: 7, name: 'Ventas' }],
        'agents/getVerifiedAgents': [{ id: 3, name: 'Ana' }],
        'inboxes/getInboxes': [
          { id: 1, captain_assistant: { id: 7, name: 'Ventas' } },
          { id: 2, captain_assistant: null },
        ],
        'labels/getLabels': [],
        'teams/getTeams': [],
      })
    );
  });

  it.each([false, true])(
    'lists only general Captain without pinned inboxes and persists the selection (macro=%s)',
    async macro => {
      const wrapper = mount(Host, { props: { macro } });
      const select = wrapper.findAllComponents(SingleSelect)[1];
      expect(select.props('options')).toEqual(
        expect.arrayContaining([
          {
            id: 'captain',
            name: 'CAPTAIN.ASSIGNMENT.GENERAL',
            icon: 'i-woot-captain',
          },
          { id: 3, name: 'Ana' },
        ])
      );
      await select.vm.$emit('update:modelValue', {
        id: 'captain:7',
        name: 'Ventas',
      });
      expect(
        actionQueryGenerator([wrapper.vm.action])[0].action_params
      ).toEqual(['captain:7']);
      expect(dispatch).toHaveBeenCalledWith('captainAssistants/get');
      wrapper.unmount();
    }
  );

  it('retains a deleted assistant when reopening and saving', () => {
    const wrapper = mount(Host, { props: { selected: 'captain:99' } });
    expect(
      wrapper.findAllComponents(SingleSelect)[1].props('options')
    ).toContainEqual({
      id: 'captain:99',
      name: 'CAPTAIN.ASSIGNMENT.DELETED',
      icon: 'i-woot-captain',
      description: 'CAPTAIN.ASSIGNMENT.UNAVAILABLE',
    });
    expect(actionQueryGenerator([wrapper.vm.action])[0].action_params).toEqual([
      'captain:99',
    ]);
    wrapper.unmount();
  });

  it('hides Captain choices without the feature', () => {
    state['accounts/isFeatureEnabledonAccount'] = () => false;
    const wrapper = mount(Host, { props: { selected: '3' } });
    expect(
      wrapper
        .findAllComponents(SingleSelect)[1]
        .props('options')
        .some(option => String(option.id).startsWith('captain'))
    ).toBe(false);
    wrapper.unmount();
  });
  it('offers general Captain even when no assistant is configured', () => {
    state['captainAssistants/getRecords'] = [];
    const wrapper = mount(Host);
    expect(
      wrapper.findAllComponents(SingleSelect)[1].props('options')[0].id
    ).toBe('captain');
    wrapper.unmount();
  });
});
