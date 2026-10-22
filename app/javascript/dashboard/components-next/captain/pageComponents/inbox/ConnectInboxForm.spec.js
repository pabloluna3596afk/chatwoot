import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import ConnectInboxForm from './ConnectInboxForm.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    computed(
      () =>
        ({
          'captainInboxes/getUIFlags': {},
          'captainInboxes/getRecords': [{ id: 1 }],
          'inboxes/getInboxes': [
            {
              id: 1,
              name: 'Current',
              captain_assistant: { id: 7, name: 'Current assistant' },
            },
            {
              id: 2,
              name: 'Occupied',
              captain_assistant: { id: 8, name: 'Soporte' },
            },
            { id: 3, name: 'Free', captain_assistant: null },
          ],
        })[key]
    ),
}));

describe('ConnectInboxForm', () => {
  it('keeps another assistant inbox visible and disabled through the real menu', async () => {
    const wrapper = mount(ConnectInboxForm, { props: { assistantId: 7 } });
    const picker = wrapper.getComponent(ComboBox);
    expect(picker.props('options').map(option => option.value)).toEqual([2, 3]);
    expect(picker.props('options')[0]).toMatchObject({ disabled: true });
    await picker.get('button').trigger('click');
    const occupied = picker.findAll('[role="option"]')[0];
    expect(occupied.text()).toContain('CAPTAIN.ASSIGNMENT.CONNECTED_TO');
    expect(occupied.attributes('disabled')).toBeDefined();
    expect(occupied.get('span').classes()).toContain('whitespace-normal');
    await occupied.trigger('click');
    expect(picker.emitted('update:modelValue')).toBeUndefined();
    await picker.findAll('[role="option"]')[1].trigger('click');
    await wrapper.get('form').trigger('submit');
    await Promise.resolve();
    expect(picker.emitted('update:modelValue')[0]).toEqual([3]);
    wrapper.unmount();
  });
});
