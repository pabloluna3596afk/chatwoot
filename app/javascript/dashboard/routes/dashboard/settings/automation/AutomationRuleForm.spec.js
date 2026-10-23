import { nextTick, reactive } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Input from 'dashboard/components-next/input/Input.vue';
import AutomationRuleForm from './AutomationRuleForm.vue';
import AutomationRunTypeSelector from './components/AutomationRunTypeSelector.vue';
import AutomationWaitCondition from './components/AutomationWaitCondition.vue';
const inboxes = vi.hoisted(() => ({ value: [] }));
const uiFlags = vi.hoisted(() => ({ value: {} }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => (key === 'automations/getUIFlags' ? uiFlags : inboxes),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

vi.mock('dashboard/components-next/filter/operators', () => ({
  useOperators: () => ({ operators: { value: {} } }),
}));

const automationTypes = Object.fromEntries(
  [
    'conversation_created',
    'conversation_updated',
    'conversation_resolved',
    'message_created',
    'conversation_opened',
  ].map(event => [event, { conditions: [] }])
);

const triggerStub = {
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const waitConditionStub = {
  props: ['isSavedWait'],
  template: '<div />',
  methods: {
    resetValidation: vi.fn(),
    validate: vi.fn(() => true),
  },
};

const instantConditions = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: 'open',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

const waitConditions = [
  {
    attribute_key: 'message_type',
    filter_operator: 'equal_to',
    values: 'outgoing',
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'private_note',
    filter_operator: 'equal_to',
    values: false,
    query_operator: 'and',
    custom_attribute_type: '',
  },
  {
    attribute_key: 'priority',
    filter_operator: 'equal_to',
    values: 'high',
    query_operator: null,
    custom_attribute_type: '',
  },
];

const buildAutomation = ({ delayed = false } = {}) => ({
  name: 'Follow up',
  description: 'Follow up after a wait',
  event_name: delayed ? 'message_created' : 'conversation_created',
  execution_delay: delayed ? 60 : null,
  conditions: structuredClone(delayed ? waitConditions : instantConditions),
  actions: [{ action_name: 'assign_agent', action_params: [] }],
  files: [],
});

const panelOpen = vi.fn();

const mountComponent = ({ mode, automation }) =>
  shallowMount(AutomationRuleForm, {
    props: {
      mode,
      automation,
      automationTypes,
      getConditionDropdownValues: vi.fn(() => []),
      getActionDropdownValues: vi.fn(() => []),
      appendNewCondition: vi.fn(),
      appendNewAction: vi.fn(),
      removeFilter: vi.fn(),
      removeAction: vi.fn(),
      resetAction: vi.fn(),
      onEventChange: vi.fn(),
    },
    global: {
      stubs: {
        SidePanel: {
          template: '<div><slot /><slot name="footer" /></div>',
          methods: {
            open: panelOpen,
            close: vi.fn(),
          },
        },
        AutomationInstantTrigger: triggerStub,
        AutomationWaitCondition: waitConditionStub,
        AutomationActions: {
          props: ['modelValue'],
          template:
            '<div><slot v-for="action in modelValue" name="captain-summary" :action="action" /></div>',
        },
        NextButton: {
          props: ['disabled', 'isLoading'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')"><slot /></button>',
        },
      },
    },
  });

const selectRunType = async (wrapper, isDelayed) => {
  wrapper
    .findComponent(AutomationRunTypeSelector)
    .vm.$emit('update:modelValue', isDelayed);
  await nextTick();
};

describe('AutomationRuleForm', () => {
  it('disables submit and shows loading while the API saves', async () => {
    uiFlags.value = { isCreating: true };
    const wrapper = mountComponent({
      mode: 'create',
      automation: buildAutomation(),
    });
    const submit = wrapper.find('button:last-child');
    expect(submit.attributes('disabled')).toBeDefined();
    await submit.trigger('click');
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('shows inline field errors and scrolls to the first one', async () => {
    const scroll = vi.fn();
    Element.prototype.scrollIntoView = scroll;
    const automation = buildAutomation();
    automation.name = '';
    automation.description = '';
    const wrapper = mountComponent({ mode: 'create', automation });
    await wrapper.find('button:last-child').trigger('click');
    await nextTick();
    expect(wrapper.findAllComponents(Input)[0].props('message')).toBe(
      'AUTOMATION.ADD.FORM.NAME.ERROR'
    );
    expect(wrapper.findAllComponents(Input)[1].props('message')).toBe(
      'AUTOMATION.ADD.FORM.DESC.ERROR'
    );
    expect(scroll).toHaveBeenCalledWith({
      block: 'center',
      behavior: 'smooth',
    });
    wrapper.unmount();
  });

  it('scrolls to server lint findings', async () => {
    const scroll = vi.fn();
    Element.prototype.scrollIntoView = scroll;
    const wrapper = mountComponent({
      mode: 'create',
      automation: buildAutomation(),
    });
    wrapper.vm.setLintFindings({ errors: [{ code: 'empty_actions' }] });
    await nextTick();
    expect(wrapper.get('[role="alert"]').text()).toContain('empty_actions');
    expect(scroll).toHaveBeenCalled();
    wrapper.unmount();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    inboxes.value = [];
    uiFlags.value = {};
  });

  it('summarizes who is assigned per inbox and flags unconnected ones without blocking editing', () => {
    inboxes.value = [
      {
        id: 1,
        name: 'Sales',
        captain_assistant: { id: 7, name: 'Sales assistant' },
      },
      { id: 2, name: 'Support', captain_assistant: null },
    ];
    const automation = buildAutomation();
    automation.conditions = [
      {
        attribute_key: 'inbox_id',
        filter_operator: 'equal_to',
        values: [{ id: 1 }, { id: 2 }],
      },
    ];
    automation.actions = [
      { action_name: 'assign_agent', action_params: [{ id: 'captain:7' }] },
    ];
    const wrapper = mountComponent({ mode: 'edit', automation });
    const summary = wrapper.get('[data-testid="captain-summary"]').text();
    expect(summary).toContain('CAPTAIN.ASSIGNMENT.SUMMARY.OK');
    expect(summary).toContain('CAPTAIN.ASSIGNMENT.SUMMARY.NONE');
    wrapper.vm.open();
    expect(panelOpen).toHaveBeenCalled();
    wrapper.unmount();
  });

  it('opens a rule whose conditions hold reactive dropdown options', async () => {
    const automation = buildAutomation();
    // Conditions hydrated from store-backed dropdowns (inboxes, agents, contacts) hold
    // reactive option objects rather than plain ones.
    automation.conditions[0].values = [reactive({ id: 1, name: 'Sales' })];
    const wrapper = mountComponent({ mode: 'edit', automation });

    wrapper.vm.open();
    await nextTick();

    expect(panelOpen).toHaveBeenCalled();
  });

  it('restores unsaved wait conditions after switching a new rule to instant and back', async () => {
    const automation = buildAutomation();
    const wrapper = mountComponent({ mode: 'create', automation });
    wrapper.vm.open();
    await nextTick();

    await selectRunType(wrapper, true);
    automation.event_name = 'message_created';
    automation.conditions = structuredClone(waitConditions);

    await selectRunType(wrapper, false);
    expect(automation.event_name).toBe('conversation_created');
    expect(automation.conditions).toEqual(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });

  it('restores saved wait conditions after editing the instant draft', async () => {
    const automation = buildAutomation({ delayed: true });
    const wrapper = mountComponent({ mode: 'edit', automation });
    wrapper.vm.open(60);
    await nextTick();

    await selectRunType(wrapper, false);
    automation.event_name = 'conversation_created';
    automation.conditions = structuredClone(instantConditions);

    await selectRunType(wrapper, true);
    expect(automation.event_name).toBe('message_created');
    expect(automation.conditions).toEqual(waitConditions);
    expect(
      wrapper.findComponent(AutomationWaitCondition).props('isSavedWait')
    ).toBe(true);
  });
});
