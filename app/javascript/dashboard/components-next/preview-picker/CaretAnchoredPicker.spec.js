import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import CaretAnchoredPicker from './CaretAnchoredPicker.vue';
import PreviewPicker from './PreviewPicker.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

describe('picker background refresh', () => {
  it('preserves selection when item IDs are unchanged and resets for a different list', async () => {
    const wrapper = shallowMount(CaretAnchoredPicker, {
      props: { items: [{ id: 1 }, { id: 2 }] },
      global: {
        stubs: {
          PreviewPicker: {
            props: ['selectedIndex'],
            methods: { scrollSelectedIntoView() {} },
            template: '<div />',
          },
          TeleportWithDirection: { template: '<div><slot /></div>' },
        },
      },
    });
    const picker = wrapper.findComponent(PreviewPicker);
    picker.vm.$emit('update:selectedIndex', 1);
    await wrapper.setProps({
      items: [{ id: 1, title: 'Refreshed' }, { id: 2 }],
    });
    expect(picker.props('selectedIndex')).toBe(1);
    await wrapper.setProps({ items: [{ id: 3 }] });
    expect(picker.props('selectedIndex')).toBe(0);
    wrapper.unmount();
  });
});
