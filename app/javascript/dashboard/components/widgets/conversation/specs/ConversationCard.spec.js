import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
};

const mountComponent = (chat, currentContact = {}, props = {}) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      inbox: { id: 1 },
      ...props,
    },
    global: {
      stubs: {
        'fluent-icon': true,
      },
    },
  });

describe('ConversationCard', () => {
  it('does not reserve the labels row when only a persisted SLA policy id is present', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the labels row when an active applied SLA is present', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the labels row when the contact is blocked', () => {
    const wrapper = mountComponent(
      {
        sla_policy_id: 1,
        applied_sla: { id: 1 },
      },
      { blocked: true }
    );

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('uses the bot icon for a Captain assignee', () => {
    const wrapper = mountComponent(
      { meta: { assignee_type: 'Captain::Assistant' } },
      {},
      { showAssignee: true, assignee: { name: 'Captain' } }
    );

    const icons = wrapper
      .findAllComponents({ name: 'Avatar' })
      .map(avatar => avatar.props('iconName'));
    expect(icons).toContain('i-lucide-bot');
  });

  it('shows Captain once, through its state avatar, while it owns the conversation', () => {
    const wrapper = mountComponent(
      {
        captain_state: 'ai',
        captain_assistant: { id: 1, name: 'Captain', thumbnail: '' },
        meta: { assignee_type: 'Captain::Assistant' },
      },
      {},
      { showAssignee: true, assignee: { name: 'Captain' } }
    );

    expect(
      wrapper.find('[data-testid="captain-assistant-avatar"]').exists()
    ).toBe(true);
    const names = wrapper
      .findAllComponents({ name: 'Avatar' })
      .map(avatar => avatar.props('name'));
    expect(names.filter(name => name === 'Captain')).toHaveLength(1);
  });
});
