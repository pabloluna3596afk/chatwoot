import { computed, defineComponent, h, nextTick, reactive } from 'vue';
import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { getDefaultConditions } from 'dashboard/helper/automationHelper';
import AutomationInstantTrigger from './AutomationInstantTrigger.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const filterKeysByEvent = {
  conversation_created: ['status', 'browser_language'],
  conversation_resolved: ['browser_language'],
};

describe('AutomationInstantTrigger', () => {
  it('switches to an event that lacks the current condition without breaking the condition row', async () => {
    const errors = [];
    const automation = reactive({
      event_name: 'conversation_created',
      conditions: getDefaultConditions('conversation_created'),
    });
    const filterTypes = computed(() =>
      filterKeysByEvent[automation.event_name].map(key => ({
        attributeKey: key,
        value: key,
        label: key,
        inputType: key === 'status' ? 'multiSelect' : 'searchSelect',
        options: [],
        filterOperators: [
          { value: 'equal_to', label: 'Equal to', hasInput: true },
        ],
      }))
    );
    const wrapper = mount(
      defineComponent({
        setup: () => () =>
          h(AutomationInstantTrigger, {
            events: Object.keys(filterKeysByEvent).map(key => ({
              key,
              value: key,
            })),
            filterTypes: filterTypes.value,
            eventName: automation.event_name,
            'onUpdate:eventName': value => {
              automation.event_name = value;
            },
            conditions: automation.conditions,
            'onUpdate:conditions': value => {
              automation.conditions = value;
            },
            appendNewCondition: vi.fn(),
            removeFilter: vi.fn(),
            onEventChange: () => {
              automation.conditions = getDefaultConditions(
                automation.event_name
              );
            },
          }),
      }),
      {
        global: {
          mocks: { $t: key => key },
          config: { errorHandler: error => errors.push(error.message) },
          stubs: {
            ComboBox: true,
            FilterSelect: true,
            SingleSelect: true,
            MultiSelect: true,
            Button: true,
          },
        },
      }
    );
    wrapper
      .findComponent({ name: 'ComboBox' })
      .vm.$emit('update:modelValue', 'conversation_resolved');
    await nextTick();

    expect(errors).toEqual([]);
    expect(automation.conditions.map(c => c.attribute_key)).toEqual([
      'browser_language',
    ]);
  });
});
