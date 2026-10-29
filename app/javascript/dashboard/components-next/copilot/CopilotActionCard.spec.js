import { mount } from '@vue/test-utils';
import OutlinedSelectField from 'dashboard/components-next/CustomAttributes/OutlinedSelectField.vue';
import CopilotActionCard from './CopilotActionCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const pendingItem = {
  id: 1,
  action: 'add_label',
  target_type: 'Conversation',
  target_id: 42,
  target_name: 'Alex',
  payload: { label_id: 9 },
  status: 'pending',
};

describe('CopilotActionCard', () => {
  it.each(['pending', 'approved', 'executed', 'rejected', 'expired', 'failed'])(
    'renders the %s state',
    status => {
      const wrapper = mount(CopilotActionCard, {
        props: { item: { ...pendingItem, status } },
        global: { mocks: { $t: key => key } },
      });

      expect(wrapper.text()).toContain(
        `CAPTAIN.COPILOT.ACTIONS.STATUS.${status.toUpperCase()}`
      );
      expect(wrapper.findAll('button')).toHaveLength(
        status === 'pending' ? 3 : 0
      );
    }
  );

  it('emits the edited payload for server revalidation', async () => {
    const wrapper = mount(CopilotActionCard, {
      props: { item: pendingItem, labels: [{ id: 9, title: 'Billing' }] },
      global: { mocks: { $t: key => key } },
    });

    const editButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CAPTAIN.COPILOT.ACTIONS.EDIT'));
    await editButton.trigger('click');
    await wrapper
      .findComponent(OutlinedSelectField)
      .vm.$emit('select', { id: 9, name: 'Billing' });
    const saveButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('CAPTAIN.COPILOT.ACTIONS.SAVE'));
    await saveButton.trigger('click');

    expect(wrapper.emitted('edit')[0][0]).toEqual({
      id: 1,
      payload: { label_id: 9 },
    });
  });
});
