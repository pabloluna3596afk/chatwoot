import { ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import CustomToolForm from './CustomToolForm.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({}),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: 1 } }),
}));
vi.mock('dashboard/api/captain/customTools', () => ({
  default: { test: vi.fn() },
}));

describe('CustomToolForm email verification setting', () => {
  it('submits the opt-in setting and preserves it when editing', async () => {
    const wrapper = shallowMount(CustomToolForm, {
      props: {
        mode: 'edit',
        tool: {
          id: 9,
          title: 'Order lookup',
          endpoint_url: 'https://example.com/orders',
          settings: { requires_email_verification: true },
        },
      },
    });

    const inputs = wrapper.findAllComponents(Input);
    await inputs[0].vm.$emit('update:modelValue', 'Order lookup');
    await inputs[1].vm.$emit('update:modelValue', 'https://example.com/orders');
    await wrapper.findComponent(Checkbox).vm.$emit('update:modelValue', true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(wrapper.emitted('submit')[0][0].settings).toEqual({
      requires_email_verification: true,
    });
    wrapper.unmount();
  });
});
