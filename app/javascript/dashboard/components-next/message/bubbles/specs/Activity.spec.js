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
        CaptainGenerationDetails: {
          props: ['messageId'],
          template: '<span data-captain-icon :data-message-id="messageId" />',
        },
        MessageSourceIndicator: {
          props: ['iconClass'],
          template: '<span data-source-icon :data-icon-class="iconClass" />',
        },
      },
    },
  });
};

describe('Activity', () => {
  it('places the compact Captain control before activity text and time', () => {
    const wrapper = mountActivity({
      activity: { source: { type: 'captain' } },
    });
    const icon = wrapper.get('[data-captain-icon]');
    expect(icon.attributes('data-message-id')).toBe('7');
    const bubble = wrapper.get('[data-bubble-name="activity"]');
    expect(bubble.classes()).toEqual(
      expect.arrayContaining([
        'mx-auto',
        'w-fit',
        'max-w-[90%]',
        'items-center',
        'justify-center',
        'px-3',
        'py-1',
      ])
    );
    expect(icon.element.parentElement.classList).toContain('size-6');
    const elements = Array.from(bubble.element.children);
    expect(elements.indexOf(icon.element)).toBeLessThan(
      elements.indexOf(wrapper.get('[data-activity-layout]').element)
    );
    expect(
      wrapper.get('[data-activity-layout] [aria-hidden="true"]').exists()
    ).toBe(true);
    wrapper.unmount();
  });

  it.each(['macro', 'automation'])(
    'places the %s source icon before activity text',
    type => {
      const wrapper = mountActivity({ messageSource: { type, id: 3 } });
      const elements = Array.from(
        wrapper.get('[data-bubble-name="activity"]').element.children
      );
      expect(
        elements.indexOf(wrapper.get('[data-source-icon]').element)
      ).toBeLessThan(
        elements.indexOf(wrapper.get('[data-activity-layout]').element)
      );
      expect(
        wrapper.get('[data-source-icon]').attributes('data-icon-class')
      ).toContain('self-start');
      expect(wrapper.find('time').exists()).toBe(true);
      wrapper.unmount();
    }
  );
  it('sanitizes activity content and adds an exact and relative timestamp', () => {
    const wrapper = mountActivity();
    const content = wrapper.get('[data-activity-content]');

    expect(content.text()).toContain('Conversation was resolved by');
    expect(content.find('img').attributes('onerror')).toBeUndefined();
    expect(wrapper.get('time').attributes('datetime')).toBe(
      new Date(1_723_456_789_000).toISOString()
    );
    expect(wrapper.get('time').text()).not.toBe('');
    wrapper.unmount();
  });

  it('keeps short activity copy and timestamp in a single centered row', () => {
    const wrapper = mountActivity(
      { activity: { source: { type: 'captain' } } },
      'Conversation resolved'
    );
    expect(wrapper.find('br').exists()).toBe(false);
    expect(wrapper.get('[data-activity-content]').text()).toBe(
      'Conversation resolved'
    );
    expect(
      wrapper.get('[data-activity-layout] [aria-hidden="true"]').exists()
    ).toBe(true);
    expect(wrapper.get('[data-bubble-name="activity"]').classes()).toContain(
      'items-center'
    );
    expect(wrapper.get('[data-captain-icon]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('keeps long activity text wrap-capable in a compact centered pill', () => {
    const wrapper = mountActivity(
      { activity: { source: { type: 'captain' } } },
      'Captain resolved the conversation after checking that no questions or requested actions remain pending.'
    );
    const bubble = wrapper.get('[data-bubble-name="activity"]');
    expect(bubble.classes()).toEqual(
      expect.arrayContaining(['mx-auto', 'w-fit', 'max-w-[90%]', 'text-center'])
    );
    expect(bubble.classes()).not.toContain('w-[90%]');
    expect(wrapper.get('[data-activity-layout]').classes()).toEqual(
      expect.arrayContaining(['min-w-0', 'flex-1', 'text-center'])
    );
    expect(bubble.classes()).not.toContain('flex-wrap');
    expect(wrapper.find('br').exists()).toBe(false);
    expect(wrapper.get('[data-activity-content]').text()).toBe(
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
