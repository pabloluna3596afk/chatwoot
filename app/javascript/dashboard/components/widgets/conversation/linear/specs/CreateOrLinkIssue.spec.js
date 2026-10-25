import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CreateOrLinkIssue from '../CreateOrLinkIssue.vue';
import Tabs from 'dashboard/components/ui/Tabs/Tabs.vue';
import TabsItem from 'dashboard/components/ui/Tabs/TabsItem.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      INTEGRATION_SETTINGS: {
        LINEAR: {
          ADD_OR_LINK: {
            TITLE: 'Add or link issue',
            DESCRIPTION: 'Choose an action',
          },
          CREATE: 'Create issue',
          LINK: {
            TITLE: 'Link issue',
            LINK_TITLE: 'Conversation {conversationId}: {name}',
          },
        },
      },
    },
  },
});

const createIssueStub = {
  props: ['accountId', 'conversationId', 'title'],
  template:
    '<section data-testid="create-issue"><button type="button" @click="$emit(\'close\')">Done</button></section>',
};

const linkIssueStub = {
  props: ['accountId', 'conversationId', 'title'],
  template: '<section data-testid="link-issue" />',
};

describe('CreateOrLinkIssue tabs', () => {
  it('switches create/link panels with arrow navigation and preserves close', async () => {
    const wrapper = mount(CreateOrLinkIssue, {
      props: {
        accountId: 42,
        conversation: { id: 7, meta: { sender: { name: 'Ada' } } },
      },
      global: {
        plugins: [i18n],
        components: {
          WootTabs: Tabs,
          WootTabsItem: TabsItem,
          WootModalHeader: { template: '<header />' },
        },
        stubs: { CreateIssue: createIssueStub, LinkIssue: linkIssueStub },
      },
    });

    expect(wrapper.find('[data-testid="create-issue"]').exists()).toBe(true);
    const createTab = wrapper.get('[role="tab"]');
    expect(createTab.attributes('aria-selected')).toBe('true');
    await createTab.trigger('keydown', { key: 'ArrowRight' });

    expect(wrapper.find('[data-testid="link-issue"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="create-issue"]').exists()).toBe(false);
    expect(wrapper.get('[role="tab"][aria-selected="true"]').text()).toBe(
      'Link issue'
    );

    await wrapper.get('[role="tab"]').trigger('click');
    await wrapper.get('[data-testid="create-issue"] button').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
