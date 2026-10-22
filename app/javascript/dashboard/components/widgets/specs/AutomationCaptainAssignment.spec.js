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
  props: { macro: Boolean, selected: { type: String, default: 'captain' } },
  setup(props) {
    const { getActionDropdownValues } = useAutomationValues();
    const { getMacroDropdownValues } = useMacros();
    const options = computed(() =>
      (props.macro ? getMacroDropdownValues : getActionDropdownValues)(
        'assign_agent'
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
  beforeEach(() => {
    Object.assign(
      state,
      reactive({
        'accounts/isFeatureEnabledonAccount': () => true,
        'captainAssistants/getRecords': [{ id: 7, name: 'Ventas' }],
        'agents/getVerifiedAgents': [{ id: 3, name: 'Ana' }],
        'labels/getLabels': [],
        'teams/getTeams': [],
      })
    );
  });

  it.each([false, true])(
    'lists general and named Captain, persists the selection (macro=%s)',
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
          { id: 'captain:7', name: 'Ventas', icon: 'i-woot-captain' },
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
    });
    expect(actionQueryGenerator([wrapper.vm.action])[0].action_params).toEqual([
      'captain:99',
    ]);
    wrapper.unmount();
  });

  it.each([false, true])(
    'hides new Captain choices without the feature or assistants (empty=%s)',
    empty => {
      state['accounts/isFeatureEnabledonAccount'] = () => empty;
      if (empty) state['captainAssistants/getRecords'] = [];
      const wrapper = mount(Host, { props: { selected: '3' } });
      const options = wrapper
        .findAllComponents(SingleSelect)[1]
        .props('options');
      expect(
        options.some(option => String(option.id).startsWith('captain'))
      ).toBe(false);
      wrapper.unmount();
    }
  );
});
