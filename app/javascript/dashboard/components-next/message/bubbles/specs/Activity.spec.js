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

  it.each(['macro', 'automation', 'flow'])(
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

  it.each([
    ['assignment', {}, 'Maria assigned this conversation to Alex Rivera'],
    ['team', {}, 'Maria assigned this conversation to Support'],
    ['label', {}, 'Maria added the label priority'],
    ['priority', {}, 'Maria changed priority to high'],
    ['resolved', {}, 'Maria resolved the conversation'],
    ['reopened', {}, 'Maria reopened the conversation'],
    ['pending', {}, 'Maria marked the conversation pending'],
    ['SLA', {}, 'Maria changed the SLA policy'],
    [
      'automation',
      { messageSource: { type: 'automation', id: 3 } },
      'Automation changed status',
    ],
    [
      'macro',
      { messageSource: { type: 'macro', id: 4 } },
      'Macro added a reply',
    ],
    [
      'flow',
      { messageSource: { type: 'flow', id: 5 } },
      'Flow updated the conversation',
    ],
  ])(
    'renders %s activity in the shared compact activity pill',
    (_type, attributes, text) => {
      const wrapper = mountActivity(attributes, text);
      const bubble = wrapper.get('[data-bubble-name="activity"]');

      expect(bubble.classes()).toEqual(
        expect.arrayContaining([
          'mx-auto',
          'w-fit',
          'max-w-[90%]',
          'px-3',
          'py-1',
        ])
      );
      expect(wrapper.get('[data-activity-content]').text()).toBe(text);
      expect(wrapper.get('time').text()).not.toBe('');
      expect(wrapper.get('[data-activity-layout]').exists()).toBe(true);
      wrapper.unmount();
    }
  );

  it('removes one final period and trailing spaces before closing HTML tags', () => {
    const wrapper = mountActivity(
      {},
      'The conversation is resolved.  <strong>Done.   </strong>   '
    );

    expect(wrapper.get('[data-activity-content]').text()).toBe(
      'The conversation is resolved.  Done'
    );
    wrapper.unmount();
  });

  it('bolds only the first exact occurrence of each supplied name', () => {
    const wrapper = mountActivity(
      { activity: { names: ['Alex Rivera'] } },
      'Maria assigned Alex Rivera to Alex Rivera Jr.'
    );

    const matches = wrapper.findAll('[data-activity-content] b.nm');
    expect(matches).toHaveLength(1);
    expect(matches[0].text()).toBe('Alex Rivera');
    expect(matches[0].classes()).toEqual(
      expect.arrayContaining(['font-semibold', 'text-n-slate-12'])
    );
    wrapper.unmount();
  });

  it('matches accented names with Unicode word boundaries', () => {
    const wrapper = mountActivity(
      { activity: { names: ['José'] } },
      'José asignó Josefa al equipo'
    );

    expect(wrapper.findAll('[data-activity-content] b.nm')).toHaveLength(1);
    expect(wrapper.get('[data-activity-content] b.nm').text()).toBe('José');
    wrapper.unmount();
  });

  it('matches names containing regular expression characters literally', () => {
    const wrapper = mountActivity(
      { activity: { names: ['A+B', 'C.D'] } },
      'A+B assigned C.D'
    );

    expect(
      wrapper.findAll('[data-activity-content] b.nm').map(node => node.text())
    ).toEqual(['A+B', 'C.D']);
    wrapper.unmount();
  });

  it('sanitizes hostile HTML before matching and never matches attributes', () => {
    const wrapper = mountActivity(
      { activity: { names: ['tracker.png', 'Agent'] } },
      maliciousContent
    );
    const content = wrapper.get('[data-activity-content]');

    expect(content.find('img').attributes('onerror')).toBeUndefined();
    expect(content.findAll('b.nm').map(node => node.text())).toEqual(['Agent']);
    wrapper.unmount();
  });

  it('does not add bold markup when activity names are absent', () => {
    const wrapper = mountActivity({}, 'Maria assigned Alex Rivera');

    expect(wrapper.find('[data-activity-content] b.nm').exists()).toBe(false);
    wrapper.unmount();
  });

  it('does not add bold markup when names occur only as part of other words', () => {
    const wrapper = mountActivity(
      { activity: { names: ['Alex'] } },
      'Alexandra assigned the conversation'
    );

    expect(wrapper.find('[data-activity-content] b.nm').exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(['Version v1.2 is active.', 'Use this etc...'])(
    'does not alter internal versions or ellipses in %s',
    text => {
      const wrapper = mountActivity({}, text);

      expect(wrapper.get('[data-activity-content]').text()).toBe(
        text.endsWith('.') && !text.endsWith('...') ? text.slice(0, -1) : text
      );
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
      'Captain resolved the conversation after checking that no questions or requested actions remain pending'
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
      'Captain resolved the conversation after checking that no questions or requested actions remain pending'
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
