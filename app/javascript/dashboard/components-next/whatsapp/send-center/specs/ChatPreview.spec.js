import { mount } from '@vue/test-utils';
import ChatPreview from '../ChatPreview.vue';
import MessagePreview from '../../WhatsAppBubble.vue';

describe('preview help', () => {
  it('renders missing-contact guidance outside the message bubble', () => {
    const wrapper = mount(ChatPreview, {
      props: { body: 'Hello', messages: ['Enter the missing contact value.'] },
    });
    const bubble = wrapper.findComponent(MessagePreview);
    const help = wrapper.get('[data-testid="preview-help"]');
    expect(bubble.text()).not.toContain('Enter the missing contact value.');
    expect(bubble.element.contains(help.element)).toBe(false);
    expect(help.text()).toBe('Enter the missing contact value.');
    expect(help.attributes('role')).toBe('status');
    wrapper.unmount();
  });
});
