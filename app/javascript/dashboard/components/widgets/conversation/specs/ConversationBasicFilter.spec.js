import { mount } from '@vue/test-utils';
import ConversationBasicFilter from '../ConversationBasicFilter.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';

const { dispatch, updateUISettings } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  updateUISettings: vi.fn(),
}));

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: key => ({
    value: key === 'getChatStatusFilter' ? 'open' : 'last_activity_at_desc',
  }),
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ConversationBasicFilter', () => {
  it('keeps the upstream status and order options in the anchored panel', async () => {
    const wrapper = mount(ConversationBasicFilter, {
      props: { isOnExpandedLayout: true },
      global: { mocks: { $t: key => key } },
    });

    await wrapper.get('button').trigger('click');

    const [statusMenu, orderMenu] = wrapper.findAllComponents(SelectMenu);
    expect(statusMenu.props('options').map(option => option.value)).toEqual([
      'open',
      'resolved',
      'pending',
      'snoozed',
      'all',
    ]);
    expect(orderMenu.props('options').map(option => option.value)).toEqual([
      'last_activity_at_asc',
      'last_activity_at_desc',
      'created_at_desc',
      'created_at_asc',
      'unread',
      'priority_desc',
      'priority_asc',
      'priority_desc_created_at_asc',
      'waiting_since_asc',
      'waiting_since_desc',
    ]);

    statusMenu.vm.$emit('update:modelValue', 'resolved');
    expect(dispatch).toHaveBeenCalledWith('setChatStatusFilter', 'resolved');
    expect(updateUISettings).toHaveBeenCalledWith({
      conversations_filter_by: {
        status: 'resolved',
        order_by: 'last_activity_at_desc',
      },
    });
  });
});
