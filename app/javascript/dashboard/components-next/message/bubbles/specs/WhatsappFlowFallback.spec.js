import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import Message from '../../Message.vue';
import WhatsappFlowSent from '../WhatsappFlowSent.vue';
import WhatsappTemplate from '../WhatsappTemplate.vue';
import TextBubble from '../Text/Index.vue';
import WhatsappFlowResponse from '../WhatsappFlowResponse.vue';

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

describe('Flow bubble selection', () => {
  it('keeps old plain text messages in TextBubble and selects the card for structured answers', async () => {
    const wrapper = shallowMount(Message, {
      props: {
        id: 1,
        conversationId: 2,
        currentUserId: 3,
        createdAt: 1723456789,
        messageType: 0,
        status: 'sent',
        content: 'Formulario completado: Nombre: Valentina',
      },
    });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    expect(wrapper.findComponent(WhatsappFlowResponse).exists()).toBe(false);
    await wrapper.setProps({
      contentAttributes: { whatsappFlowResponse: { full_name: 'Valentina' } },
    });
    expect(wrapper.findComponent(WhatsappFlowResponse).exists()).toBe(true);
    expect(wrapper.findComponent(TextBubble).exists()).toBe(false);
  });
  it('selects outgoing snapshots before attachments and preserves private, deleted and CSAT messages', async () => {
    const wrapper = shallowMount(Message, {
      props: {
        id: 1,
        conversationId: 2,
        currentUserId: 3,
        createdAt: 1723456789,
        messageType: 1,
        status: 'sent',
        content: 'Old text',
      },
    });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    await wrapper.setProps({
      additionalAttributes: { whatsappFlow: { name: 'Booking', cta: 'Open' } },
    });
    expect(wrapper.findComponent(WhatsappFlowSent).exists()).toBe(true);
    await wrapper.setProps({ private: true });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    await wrapper.setProps({
      private: false,
      contentAttributes: { deleted: true },
    });
    expect(wrapper.findComponent(TextBubble).exists()).toBe(true);
    await wrapper.setProps({
      contentAttributes: {},
      additionalAttributes: { templateParams: { name: 'confirm' } },
      attachments: [{ fileType: 'image' }],
    });
    expect(wrapper.findComponent(WhatsappTemplate).exists()).toBe(true);
    await wrapper.setProps({ contentType: 'input_csat' });
    expect(wrapper.findComponent(WhatsappTemplate).exists()).toBe(false);
    await wrapper.setProps({ contentType: 'text', messageType: 0 });
    expect(wrapper.findComponent(WhatsappTemplate).exists()).toBe(false);
  });
});
