import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import Activity from '../Activity.vue';
import { provideMessageContext } from '../../provider.js';

const maliciousContent =
  'Conversation was resolved by <img src="https://example.com/tracker.png" onerror="alert(1)">Agent';

const mountActivity = (attributes = {}, activityContent = maliciousContent) => {
  const TestHost = defineComponent({
    components: { Activity },
    setup() {
      provideMessageContext({
        content: ref(activityContent),
        createdAt: ref(1_723_456_789),
        id: ref(7),
        contentAttributes: ref(attributes),
      });
    },
    template: '<Activity />',
  });

  return mount(TestHost, {
    global: {
      plugins: [VueDOMPurifyHTML],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        CaptainGenerationDetails: true,
      },
    },
  });
};

describe('Activity', () => {
  it('places Captain details after the activity timestamp', () => {
    const wrapper = mountActivity({
      activity: { source: { type: 'captain' } },
    });
    const details = wrapper.findComponent({ name: 'CaptainGenerationDetails' });
    expect(details.props('messageId')).toBe(7);
    expect(wrapper.get('time').element.nextElementSibling).toBe(
      details.element
    );
    wrapper.unmount();
  });
  it('sanitizes activity content and adds an exact and relative timestamp', () => {
    const wrapper = mountActivity();
    const content = wrapper.find('span');

    expect(content.text()).toContain('Conversation was resolved by');
    expect(content.find('img').attributes('onerror')).toBeUndefined();
    expect(wrapper.get('time').attributes('datetime')).toBe(
      new Date(1_723_456_789_000).toISOString()
    );
    expect(wrapper.get('time').text()).not.toBe('');
    wrapper.unmount();
  });

  it('keeps short activity copy, time, and Captain access in inline flow', () => {
    const wrapper = mountActivity(
      { activity: { source: { type: 'captain' } } },
      'Conversation resolved'
    );
    expect(wrapper.find('br').exists()).toBe(false);
    expect(
      wrapper.find('time').element.previousElementSibling.textContent
    ).toBe('Conversation resolved');
    expect(wrapper.find('time').element.parentElement.className).not.toContain(
      'flex-wrap'
    );
    expect(
      wrapper.findComponent({ name: 'CaptainGenerationDetails' }).exists()
    ).toBe(true);
    wrapper.unmount();
  });

  it('centers a long activity in the same bounded column without forced breaks', () => {
    const wrapper = mountActivity(
      { activity: { source: { type: 'captain' } } },
      'Captain resolved the conversation after checking that no questions or requested actions remain pending.'
    );
    const bubble = wrapper.get('[data-bubble-name="activity"]');
    expect(bubble.classes()).toEqual(
      expect.arrayContaining(['mx-auto', 'w-[90%]', 'text-center'])
    );
    expect(wrapper.find('br').exists()).toBe(false);
    expect(wrapper.get('time').element.previousElementSibling.textContent).toBe(
      'Captain resolved the conversation after checking that no questions or requested actions remain pending.'
    );
    wrapper.unmount();
  });

  it('keeps activity content centered in a right-to-left conversation', () => {
    const wrapper = mountActivity({}, 'تم إغلاق المحادثة');
    const bubble = wrapper.get('[data-bubble-name="activity"]');
    bubble.element.setAttribute('dir', 'rtl');
    expect(bubble.classes()).toContain('text-center');
    expect(bubble.attributes('dir')).toBe('rtl');
    expect(wrapper.find('br').exists()).toBe(false);
    wrapper.unmount();
  });
});
