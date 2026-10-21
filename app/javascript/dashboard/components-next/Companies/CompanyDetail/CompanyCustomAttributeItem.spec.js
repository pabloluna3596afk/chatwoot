import { mount } from '@vue/test-utils';
import CompanyCustomAttributeItem from './CompanyCustomAttributeItem.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';

const update = vi.fn();
const deleteCustomAttributes = vi.fn();
vi.mock('dashboard/stores/companies', () => ({
  useCompaniesStore: () => ({ update, deleteCustomAttributes }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

it('protects company formulas in the existing attribute editor', async () => {
  const wrapper = mount(CompanyCustomAttributeItem, {
    props: {
      companyId: 1,
      attribute: {
        attributeKey: 'computed',
        attributeDisplayType: 'number',
        attributeDisplayName: 'Total',
        value: 3,
        managedBy: 'formula',
      },
      isEditingView: true,
    },
  });
  const field = wrapper.findComponent(OtherAttribute);
  expect(field.props('readOnly')).toBe(true);
  await field.vm.$emit('update', 99);
  await field.vm.$emit('delete');
  expect(update).not.toHaveBeenCalled();
  expect(deleteCustomAttributes).not.toHaveBeenCalled();
});
