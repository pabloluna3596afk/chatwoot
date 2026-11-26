import { mount } from '@vue/test-utils';
import ConditionRow from '../ConditionRow.vue';

const filterTypes = [
  {
    attributeKey: 'message_time_window',
    label: 'Hora del mensaje',
    inputType: 'plainText',
    filterOperators: [
      {
        value: 'equal_to',
        label: 'Dentro de',
        hasInput: true,
        inputOverride: 'timeWindow',
        inputLayout: 'stacked',
      },
    ],
  },
  {
    attributeKey: 'status',
    label: 'Estado',
    inputType: 'plainText',
    filterOperators: [
      { value: 'equal_to', label: 'es igual a', hasInput: true },
    ],
  },
];

const mountRow = attributeKey =>
  mount(ConditionRow, {
    props: {
      attributeKey,
      filterOperator: 'equal_to',
      values: '',
      filterTypes,
    },
    global: {
      stubs: {
        FilterSelect: { template: '<div />' },
        Button: { template: '<button />' },
        TimeWindowInput: {
          template: '<div data-testid="time-window-input" />',
        },
        Input: { template: '<input />' },
      },
    },
  });

describe('ConditionRow time window layout', () => {
  it('puts the time window on a full-width row and keeps remove beside the selectors', () => {
    const wrapper = mountRow('message_time_window');
    const input = wrapper.get('[data-testid="time-window-input"]');
    const removeButton = wrapper.findAll('button').at(-1);

    expect(wrapper.get('li').classes()).toContain('min-w-0');
    expect(wrapper.get('li > div').classes()).toContain('flex-wrap');
    expect(input.classes()).toEqual(
      expect.arrayContaining(['basis-full', 'order-2', 'w-full', 'min-w-0'])
    );
    expect(removeButton.classes()).toEqual(
      expect.arrayContaining(['order-1', 'ms-auto'])
    );
    wrapper.unmount();
  });

  it('keeps regular condition inputs in their existing inline layout', () => {
    const wrapper = mountRow('status');

    expect(wrapper.find('[data-testid="time-window-input"]').exists()).toBe(
      false
    );
    expect(wrapper.findAll('button')).toHaveLength(1);
    expect(wrapper.find('.basis-full').exists()).toBe(false);
    wrapper.unmount();
  });
});
