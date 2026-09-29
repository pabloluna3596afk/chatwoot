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
        CARD: { CAPTAIN_STATE_AI: 'AI', CAPTAIN_STATE_ESCALATED: 'Escalated' },
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
  it('renders a green AI pill when the conversation is attended by AI', () => {
    const wrapper = mountBadge('ai');
    const badge = wrapper.find('[data-testid="captain-state-badge"]');

    expect(badge.text()).toBe('AI');
    expect(badge.classes()).toContain('text-n-teal-11');
  });

  it('renders a red Escalated pill when the conversation was handed off', () => {
    const wrapper = mountBadge('escalated');
    const badge = wrapper.find('[data-testid="captain-state-badge"]');

    expect(badge.text()).toBe('Escalated');
    expect(badge.classes()).toContain('text-n-ruby-11');
  });

  it.each([null, undefined])('renders nothing when captain_state is %s', v => {
    expect(
      mountBadge(v).find('[data-testid="captain-state-badge"]').exists()
    ).toBe(false);
  });
});

describe('ConversationCard captain badge', () => {
  const mountCard = captainState =>
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
          captain_state: captainState,
        },
        currentContact: { name: 'Jane Doe', thumbnail: '' },
        inbox: { id: 1 },
      },
      global: {
        plugins: [i18n],
        stubs: {
          'fluent-icon': true,
          Avatar: true,
          TimeAgo: true,
          MessagePreview: true,
          PanelIaStateIndicator: true,
        },
      },
    });

  it('shows the badge only when captain_state is present', () => {
    expect(
      mountCard('escalated').findComponent(CaptainStateBadge).exists()
    ).toBe(true);
    expect(mountCard(null).findComponent(CaptainStateBadge).exists()).toBe(
      false
    );
  });
});
