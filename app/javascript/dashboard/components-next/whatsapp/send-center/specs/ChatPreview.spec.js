import { mount } from '@vue/test-utils';
import ChatPreview from '../ChatPreview.vue';
import MessagePreview from '../../WhatsAppBubble.vue';

it('anchors the bubble above fixed-height human help without missing-contact messages', async () => {
  const wrapper = mount(ChatPreview, {
    props: { body: 'Hello', fieldHint: 'Contact name' },
  });
  const bubble = wrapper.findComponent(MessagePreview);
  const hint = wrapper.get('[data-testid=preview-field-hint]');
  expect(hint.text()).toBe('Contact name');
  expect(hint.classes()).toContain('h-10');
  expect(hint.attributes('aria-live')).toBe('polite');
  expect(bubble.element.contains(hint.element)).toBe(false);
  expect(wrapper.find('.my-auto').exists()).toBe(false);
  expect(wrapper.find('[data-testid=preview-help]').exists()).toBe(false);
  await wrapper.setProps({ fieldHint: '' });
  expect(hint.classes()).toContain('h-10');
  wrapper.unmount();
});
