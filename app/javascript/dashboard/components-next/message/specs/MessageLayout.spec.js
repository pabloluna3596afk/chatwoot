import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import Message from '../Message.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '2' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    ref(
      key === 'inboxes/getInbox'
        ? () => ({ channel_type: 'Channel::Whatsapp' })
        : () => false
    ),
}));
vi.mock(
  'dashboard/modules/conversations/components/MessageContextMenu.vue',
  () => ({ default: { template: '<div />' } })
);

describe('grouped message spacing', () => {
  it.each([
    ['text', {}],
    ['private note', { private: true }],
    [
      'attachment',
      {
        content: null,
        attachments: [{ fileType: 'file', dataUrl: '/file.pdf' }],
      },
    ],
    [
      'template',
      { additionalAttributes: { templateParams: { name: 'confirm' } } },
    ],
    [
      'incoming without avatar',
      { messageType: 0, sender: { id: 9, type: 'Contact' } },
    ],
  ])(
    'uses a compact gap for intermediate %s messages and restores the group boundary',
    async (_name, overrides) => {
      const wrapper = shallowMount(Message, {
        props: {
          id: 1,
          conversationId: 2,
          currentUserId: 3,
          createdAt: 1795125601,
          messageType: 1,
          status: 'sent',
          content: 'Message',
          groupWithNext: true,
          sender: { id: 3, type: 'User' },
          ...overrides,
        },
      });
      expect(wrapper.classes()).toContain('mb-0.5');
      expect(wrapper.classes()).not.toContain('mb-2');
      expect(wrapper.findComponent({ name: 'Avatar' }).exists()).toBe(false);
      await wrapper.setProps({ groupWithNext: false });
      expect(wrapper.classes()).toContain('mb-2');
      expect(wrapper.classes()).not.toContain('mb-0.5');
      expect(wrapper.findComponent({ name: 'Avatar' }).exists()).toBe(
        overrides.messageType !== 0
      );
      wrapper.unmount();
    }
  );
});

describe('message sender identity', () => {
  it.each([
    ['en', null, {}, 'System'],
    ['es', null, {}, 'Sistema'],
    [
      'en',
      { type: 'agent_bot', name: 'Sales connector' },
      {},
      'Sales connector',
    ],
    [
      'es',
      { type: 'agent_bot', name: 'Conector de ventas' },
      {},
      'Conector de ventas',
    ],
    ['en', { type: 'User', name: 'Alice' }, {}, 'Alice'],
    ['en', null, { senderName: 'Slack user' }, 'Slack user'],
  ])(
    'renders %s sender as %s',
    (locale, sender, additionalAttributes, expected) => {
      const wrapper = shallowMount(Message, {
        props: {
          id: 1,
          conversationId: 2,
          currentUserId: 3,
          createdAt: 1795125601,
          messageType: 1,
          status: 'sent',
          content: 'Hello',
          sender,
          additionalAttributes,
        },
        global: {
          plugins: [
            createI18n({ legacy: false, locale, messages: { en, es } }),
          ],
          stubs: {
            Avatar: {
              props: ['name'],
              template: '<span class="sender-name">{{ name }}</span>',
            },
          },
        },
      });
      expect(wrapper.get('.sender-name').text()).toBe(expected);
      wrapper.unmount();
    }
  );
});
