import { shallowMount } from '@vue/test-utils';
import ParamRow from './ParamRow.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

it('marks a string parameter as filled with the verified email', async () => {
  const wrapper = shallowMount(ParamRow, {
    props: { name: 'email', type: 'string', description: 'Customer email' },
  });

  await wrapper
    .findAllComponents(Checkbox)[1]
    .vm.$emit('update:modelValue', true);

  expect(wrapper.emitted('update:source')[0]).toEqual(['verified.email']);
  wrapper.unmount();
});
