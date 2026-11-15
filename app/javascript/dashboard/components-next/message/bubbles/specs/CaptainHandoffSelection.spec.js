import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import Message from '../../Message.vue';
import CaptainHandoff from '../CaptainHandoff.vue';
import TextBubble from '../Text/Index.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '2' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    ref(key === 'inboxes/getInbox' ? () => ({}) : () => false),
}));
vi.mock(
  'dashboard/modules/conversations/components/MessageContextMenu.vue',
  () => ({
    default: { template: '<div />' },
  })
);

const props = {
  id: 1,
  conversationId: 2,
  currentUserId: 3,
  createdAt: 1723456789,
  messageType: 1,
  status: 'sent',
  content: 'Needs a person',
};

describe('Captain handoff bubble selection', () => {
  it('uses the handoff card for private notes with handoff data', () => {
    const wrapper = shallowMount(Message, {
      props: {
        ...props,
        private: true,
        contentAttributes: { captainHandoff: { reasonCategory: 'unknown' } },
      },
    });
    expect(wrapper.findComponent(CaptainHandoff).exists()).toBe(true);
    expect(wrapper.findComponent(TextBubble).exists()).toBe(false);
  });

  it('keeps the plain note otherwise', async () => {
    const wrapper = shallowMount(Message, {
      props: { ...props, private: true },
    });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    await wrapper.setProps({
      private: false,
      contentAttributes: { captainHandoff: {} },
    });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    expect(wrapper.findComponent(CaptainHandoff).exists()).toBe(false);
  });
});
