import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CaptainStateBadge from '../CaptainStateBadge.vue';
import ConversationCard from '../ConversationCard.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      CONVERSATION: {
        CARD: {
          CAPTAIN_STATE_ESCALATED: 'Escalated',
          CAPTAIN_ANSWERING: '{name} · answering',
          CAPTAIN_WAITING_CUSTOMER: '{name} · waiting for the customer',
        },
      },
    },
  },
});

const mountBadge = captainState =>
  mount(CaptainStateBadge, {
    props: { chat: { id: 1, captain_state: captainState } },
    global: { plugins: [i18n] },
  });

describe('CaptainStateBadge', () => {
  it('renders a pulsing red Escalated pill when the conversation was handed off', () => {
    const wrapper = mountBadge('escalated');
    const badge = wrapper.find('[data-testid="captain-state-badge"]');

    expect(badge.text()).toBe('Escalated');
    expect(badge.classes()).toContain('text-n-ruby-11');
    expect(badge.classes()).toContain('animate-pulse');
  });

  it.each(['ai', null, undefined])(
    'renders nothing when captain_state is %s',
    v => {
      expect(
        mountBadge(v).find('[data-testid="captain-state-badge"]').exists()
      ).toBe(false);
    }
  );
});

describe('ConversationCard captain state', () => {
  const assistant = { id: 7, name: 'Sofia', thumbnail: 'https://x/s.png' };
  const message = message_type => ({ id: 1, message_type, content: 'hi' });

  const mountCard = ({ chat = {}, showAssignee = false, assignee } = {}) =>
    mount(ConversationCard, {
      props: {
        chat: {
          id: 1,
          labels: [],
          messages: [],
          priority: null,
          unread_count: 0,
          timestamp: 1700000000,
          created_at: 1700000000,
          ...chat,
        },
        currentContact: { name: 'Jane Doe', thumbnail: '' },
        inbox: { id: 1 },
        showAssignee,
        assignee,
      },
      global: {
        plugins: [i18n],
        directives: { tooltip: () => {} },
        stubs: {
          'fluent-icon': true,
          Avatar: true,
          TimeAgo: true,
          MessagePreview: true,
          PanelIaStateIndicator: true,
        },
      },
    });

  const ring = wrapper =>
    wrapper.find('[data-testid="captain-assistant-avatar"]');

  it('shows a teal ring when Captain is answering (last message from the contact)', () => {
    const wrapper = mountCard({
      chat: {
        captain_state: 'ai',
        captain_assistant: assistant,
        messages: [message(0)],
      },
    });

    expect(ring(wrapper).exists()).toBe(true);
    expect(ring(wrapper).classes()).toContain('ring-n-teal-9');
    expect(ring(wrapper).classes()).not.toContain('ring-n-amber-9');
    expect(wrapper.find('[data-testid="captain-state-badge"]').exists()).toBe(
      false
    );
  });

  it('shows an amber ring when Captain is waiting for the customer', () => {
    const wrapper = mountCard({
      chat: {
        captain_state: 'ai',
        captain_assistant: assistant,
        messages: [message(0), message(1)],
      },
    });

    expect(ring(wrapper).classes()).toContain('ring-n-amber-9');
    expect(ring(wrapper).classes()).not.toContain('ring-n-teal-9');
  });

  it('ignores activity messages when picking the ring color', () => {
    const wrapper = mountCard({
      chat: {
        captain_state: 'ai',
        captain_assistant: assistant,
        messages: [message(1), message(2)],
      },
    });

    expect(ring(wrapper).classes()).toContain('ring-n-amber-9');
  });

  it('keeps the red Escalated label and no assistant ring when escalated', () => {
    const wrapper = mountCard({
      chat: { captain_state: 'escalated', messages: [message(1)] },
    });

    expect(ring(wrapper).exists()).toBe(false);
    const badge = wrapper.find('[data-testid="captain-state-badge"]');
    expect(badge.text()).toBe('Escalated');
    expect(badge.classes()).toContain('animate-pulse');
  });

  it('is unchanged for a human assignee', () => {
    const wrapper = mountCard({
      chat: { captain_state: null, meta: { assignee_type: 'User' } },
      showAssignee: true,
      assignee: { id: 3, name: 'Agent Smith' },
    });

    expect(ring(wrapper).exists()).toBe(false);
    expect(wrapper.findAllComponents({ name: 'Avatar' })).toHaveLength(2);
    expect(wrapper.find('[data-testid="captain-state-badge"]').exists()).toBe(
      false
    );
  });

  it('is unchanged for an AgentBot assignee', () => {
    const wrapper = mountCard({
      chat: {
        captain_state: null,
        captain_assistant: null,
        meta: { assignee_type: 'AgentBot' },
      },
      showAssignee: true,
      assignee: { id: 9, name: 'Bot' },
    });

    expect(ring(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-testid="captain-state-badge"]').exists()).toBe(
      false
    );
  });
});
