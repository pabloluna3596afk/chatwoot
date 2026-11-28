import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import ConditionRow from './ConditionRow.vue';
import FilterSelect from './inputs/FilterSelect.vue';
import { buildAttributesFilterTypes } from './helper/filterHelper';
import { useOperators } from './operators';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('ConditionRow numeric operator validation', () => {
  it.each(
    ['number', 'currency', 'percent'].flatMap(type =>
      ['contains', 'does_not_contain'].map(operator => [type, operator])
    )
  )(
    'blocks a saved numeric custom attribute filter of type %s using %s until its operator is corrected',
    async (attributeDisplayType, filterOperator) => {
      const { getOperatorTypes } = useOperators();
      const filterTypes = buildAttributesFilterTypes(
        [
          {
            attributeKey: 'contract_count',
            attributeDisplayName: 'Contract count',
            attributeDisplayType,
          },
        ],
        getOperatorTypes,
        'contact'
      );
      const wrapper = shallowMount(ConditionRow, {
        props: {
          filterTypes,
          attributeKey: 'contract_count',
          filterOperator,
          values: '12',
        },
      });

      const operatorPicker = wrapper.findAllComponents(FilterSelect)[1];
      expect(operatorPicker.props('options').map(({ value }) => value)).toEqual(
        [
          'equal_to',
          'not_equal_to',
          'is_present',
          'is_not_present',
          'is_greater_than',
          'is_less_than',
        ]
      );
      expect(wrapper.vm.validate()).toBe(false);
      await wrapper.vm.$nextTick();
      expect(wrapper.text()).toContain('FILTER.ERRORS.INVALID_FILTER_OPERATOR');

      await wrapper.setProps({ filterOperator: 'equal_to' });
      expect(wrapper.vm.validate()).toBe(true);
      expect(wrapper.text()).not.toContain(
        'FILTER.ERRORS.INVALID_FILTER_OPERATOR'
      );
    }
  );
});
