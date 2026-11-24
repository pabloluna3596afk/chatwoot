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

it.each([
  ['formula', 'total_citas', 'number', 3],
  ['calendar', 'total_citas', 'number', 3],
  ['calendar', 'estado_proxima_cita', 'text', 'confirmed'],
  ['calendar', 'citas_canceladas', 'number', 2],
])(
  'MV-14: prevents editing and deleting %s field %s',
  async (managedBy, attributeKey, attributeDisplayType, value) => {
    const wrapper = mount(ContactCustomAttributeItem, {
      props: {
        attribute: {
          attributeKey,
          attributeDisplayType,
          attributeDisplayName: attributeKey,
          value,
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
