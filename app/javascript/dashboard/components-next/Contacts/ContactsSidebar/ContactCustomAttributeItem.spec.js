import { mount } from '@vue/test-utils';
import ContactCustomAttributeItem from './ContactCustomAttributeItem.vue';
import OtherAttribute from 'dashboard/components-next/CustomAttributes/OtherAttribute.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { contactId: 1 } }),
}));
const dispatch = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

it.each(['calendar', 'formula'])(
  'MV-14: prevents editing and deleting fields managed by %s',
  async managedBy => {
    const wrapper = mount(ContactCustomAttributeItem, {
      props: {
        attribute: {
          attributeKey: 'total_citas',
          attributeDisplayType: 'number',
          attributeDisplayName: 'Total',
          value: 3,
          managedBy,
        },
        isEditingView: true,
      },
    });
    const field = wrapper.findComponent(OtherAttribute);
    expect(field.props('readOnly')).toBe(true);
    await field.vm.$emit('update', 99);
    expect(dispatch).not.toHaveBeenCalled();
    expect(wrapper.find('button').exists()).toBe(false);
  }
);
