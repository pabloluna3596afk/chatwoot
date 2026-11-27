import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversation.json';
import chatlist from 'dashboard/i18n/locale/en/chatlist.json';
import MessageMeta from '../MessageMeta.vue';

const context = {};
const inbox = {};
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));
vi.mock('dashboard/composables/useInbox', () => ({ useInbox: () => inbox }));

const render = (props = {}, captain = false) =>
  mount(MessageMeta, {
    props,
    slots: captain
      ? { captain: '<button aria-label="Captain details" />' }
      : {},
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...en, ...chatlist } },
        }),
      ],
      directives: { tooltip: {} },
    },
  });

describe('message metadata', () => {
  it('keeps time on one line and status icons at a fixed size', () => {
    const wrapper = render();
    expect(wrapper.classes()).toContain('whitespace-nowrap');
    expect(wrapper.get('[role="img"]').classes()).toContain('shrink-0');
    wrapper.unmount();
  });
  beforeEach(() => {
    [
      'isAFacebookInbox',
      'isALineChannel',
      'isASmsInbox',
      'isATelegramChannel',
      'isATwilioChannel',
      'isAWebWidgetInbox',
      'isAWhatsAppChannel',
      'isAnInstagramChannel',
      'isATiktokChannel',
    ].forEach(name => {
      inbox[name] = ref(false);
    });
    Object.assign(context, {
      status: ref('read'),
      isPrivate: ref(false),
      createdAt: ref(1795125600),
      sourceId: ref('provider-id'),
      messageType: ref(1),
      contentAttributes: ref({}),
    });
    Object.assign(inbox, {
      isAPIInbox: ref(true),
      isAnEmailChannel: ref(false),
    });
  });

  it.each(['macro', 'automation', 'flow'])(
    'orders %s, Captain, lock, time and status in the DOM',
    type => {
      context.contentAttributes.value = {
        messageSource: { type, name: 'Demo', id: 3 },
      };
      const wrapper = render({}, true);
      const elements = wrapper.element.children;
      expect(elements[0].getAttribute('data-testid')).toBe(
        'message-source-indicator'
      );
      expect(elements[0].getAttribute('aria-label')).toContain('Demo');
      expect(elements[0].classList.contains('size-4')).toBe(true);
      expect(elements[1].tagName).toBe('BUTTON');
      expect(elements[2].tagName).toBe('TIME');
      expect(elements[3].getAttribute('role')).toBe('img');
      expect(elements[3].classList.contains('size-3.5')).toBe(true);
      wrapper.unmount();
    }
  );

  it.each(['sent', 'delivered', 'read', 'progress'])(
    'keeps %s icons in the standard metadata row',
    status => {
      inbox.isAPIInbox = ref(true);
      context.status.value = status;
      context.contentAttributes.value = {
        messageSource: { type: 'flow', id: 9 },
      };
      const wrapper = render({}, true);
      const source = wrapper.get('[data-testid="message-source-indicator"]');
      expect(source.classes()).toContain('text-n-slate-11');
      const tick = wrapper.getComponent({ name: 'MessageStatus' });
      expect(tick.classes()).toContain(
        status === 'read' ? 'text-n-blue-11' : 'text-n-slate-10'
      );
      expect([...wrapper.element.children].map(el => el.tagName)).toEqual([
        'SPAN',
        'BUTTON',
        'TIME',
        'SPAN',
      ]);
      wrapper.unmount();
    }
  );

  it('retains the origin before the private lock and hides delivery status', () => {
    context.isPrivate.value = true;
    context.contentAttributes.value = {
      messageSource: { type: 'macro', name: 'Note' },
    };
    const wrapper = render({}, true);
    expect(
      [...wrapper.element.children].map(element => element.tagName)
    ).toEqual(['SPAN', 'BUTTON', 'SPAN', 'TIME']);
    expect(wrapper.get('[aria-label="Private note"]').classes()).toContain(
      'size-3'
    );
    wrapper.unmount();
  });

  it('keeps source and Captain on intermediate grouped messages, hiding time and ticks', () => {
    context.contentAttributes.value = {
      messageSource: { type: 'flow', id: 9 },
    };
    const wrapper = render({ showTimestamp: false }, true);
    expect(wrapper.findAll('[role="img"]')).toHaveLength(1);
    expect(wrapper.find('button').exists()).toBe(true);
    expect(wrapper.find('time').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('undefined');
    wrapper.unmount();
  });

  it('renders a machine readable timestamp with an exact accessible date', () => {
    const wrapper = render();
    expect(wrapper.get('time').attributes('datetime')).toBe(
      new Date(1795125600000).toISOString()
    );
    expect(wrapper.get('time').attributes('aria-label')).toContain('2026');
    wrapper.unmount();
  });

  it.each([{ deleted: true }, { failed: true }, { private: true }])(
    'preserves exclusions for %j',
    condition => {
      context.isPrivate.value = !!condition.private;
      context.status.value = condition.failed ? 'failed' : 'read';
      context.contentAttributes.value = { deleted: !!condition.deleted };
      const wrapper = render();
      expect(wrapper.find('[aria-label="Read"]').exists()).toBe(false);
      wrapper.unmount();
    }
  );

  it('preserves the email source-id delivery rule', () => {
    inbox.isAnEmailChannel.value = true;
    context.status.value = 'sent';
    const wrapper = render();
    expect(wrapper.find('[aria-label="Sent successfully"]').exists()).toBe(
      true
    );
    wrapper.unmount();
  });
});
