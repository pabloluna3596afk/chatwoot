import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
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
