import { mount } from '@vue/test-utils';
import ChatPreview from '../ChatPreview.vue';
import MessagePreview from '../../WhatsAppBubble.vue';

describe('preview help', () => {
  it('renders missing-contact guidance outside the message bubble', () => {
    const wrapper = mount(ChatPreview, {
      props: {
        body: 'Hello',
        fieldHint: 'Detail 1 of 3 · E.g.: Alex',
        messages: ['Enter the missing contact value.'],
      },
    });
    const bubble = wrapper.findComponent(MessagePreview);
    const help = wrapper.get('[data-testid="preview-help"]');
    expect(bubble.text()).not.toContain('Enter the missing contact value.');
    expect(bubble.element.contains(help.element)).toBe(false);
    expect(help.text()).toBe('Enter the missing contact value.');
    expect(help.attributes('role')).toBe('status');
    const hint = wrapper.get('[data-testid="preview-field-hint"]');
    expect(hint.attributes('aria-live')).toBe('polite');
    expect(bubble.element.contains(hint.element)).toBe(false);
    expect(hint.element.nextElementSibling).toBe(help.element);
    expect(hint.text()).toBe('Detail 1 of 3 · E.g.: Alex');
    wrapper.unmount();
  });
});
