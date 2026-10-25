import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationBox from '../ConversationBox.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';

vi.mock('../ConversationHeader.vue', () => ({
  default: { template: '<header />' },
}));
vi.mock('../DashboardApp/Frame.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../EmptyState/EmptyState.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../MessagesView.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../PanelIaHandoffBanner.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock(
  'dashboard/components-next/InternalTasks/ConversationTaskForm.vue',
  () => ({ default: { template: '<div />' } })
);
vi.mock('dashboard/featureFlags', () => ({
  FEATURE_FLAGS: { INTERNAL_TASKS: 'internal_tasks' },
}));

describe('ConversationBox dashboard app tabs', () => {
  it('changes the active app using the shared tab keyboard behavior', async () => {
    const store = createStore({
      getters: {
        getSelectedChat: () => ({ id: 1, inbox_id: 2 }),
        getCurrentAccountId: () => 1,
        'dashboardApps/getRecords': () => [
          { id: 10, title: 'First app', content: [] },
          { id: 11, title: 'Second app', content: [] },
        ],
        'accounts/isFeatureEnabledonAccount': () => () => false,
      },
    });
    store.dispatch = vi.fn();

    const wrapper = mount(ConversationBox, {
      global: {
        plugins: [store],
        mocks: { $t: key => key },
        components: { WootTabs: Tabs, WootTabsItem: TabsItem },
      },
    });

    const tabs = wrapper.findAll('[role="tab"]');
    expect(tabs).toHaveLength(3);
    expect(tabs[0].attributes('aria-selected')).toBe('true');

    await tabs[0].trigger('keydown', { key: 'ArrowRight' });

    expect(tabs[1].attributes('aria-selected')).toBe('true');
    expect(tabs[1].attributes('tabindex')).toBe('0');
    wrapper.unmount();
  });
});
