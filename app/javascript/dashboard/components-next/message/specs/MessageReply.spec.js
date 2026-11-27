import { nextTick, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import Message from '../Message.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';

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

const render = (props = {}) =>
  shallowMount(Message, {
    props: {
      id: 1,
      conversationId: 2,
      currentUserId: 3,
      createdAt: 1795125601,
      messageType: 0,
      status: 'sent',
      content: 'Message',
      inboxSupportsReplyTo: { outgoing: true },
      sender: { id: 9, type: 'Contact' },
      ...props,
    },
    global: { stubs: { Button: false } },
  });

describe('message reply shortcuts', () => {
  it.each([
    [{}, true],
    [{ inboxSupportsReplyTo: {} }, false],
    [{ private: true }, false],
    [{ status: 'failed' }, false],
    [{ status: 'progress' }, false],
    [{ messageType: 2 }, false],
    [{ contentAttributes: { isUnsupported: true } }, false],
  ])(
    'uses menu eligibility for arrow and double click: %j',
    async (props, allowed) => {
      const emit = vi.spyOn(emitter, 'emit');
      const wrapper = render(props);
      expect(wrapper.find('[data-reply-button]').exists()).toBe(allowed);
      const surface = wrapper.find('[data-reply-surface]');
      if (surface.exists()) await surface.trigger('dblclick', { button: 0 });
      expect(
        emit.mock.calls.filter(
          ([event]) => event === BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE
        )
      ).toHaveLength(allowed ? 1 : 0);
      wrapper.unmount();
    }
  );

  it('uses the existing reply handler for click and clears double-click word selection', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = render();
    const button = wrapper.get('[data-reply-button]');
    expect(button.attributes('aria-label')).toBe('CONVERSATION.REPLYBOX.REPLY');
    expect(button.classes()).toContain('-end-11');
    expect(button.classes()).toContain('group-focus-within/reply:opacity-100');
    await button.trigger('click');
    const remove = vi.spyOn(window.getSelection(), 'removeAllRanges');
    await wrapper
      .get('[data-reply-surface]')
      .trigger('dblclick', { button: 0 });
    expect(remove).toHaveBeenCalledOnce();
    expect(
      emit.mock.calls.filter(
        ([event]) => event === BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE
      )
    ).toHaveLength(2);
    await wrapper.setProps({ messageType: 1, sender: { id: 3, type: 'User' } });
    expect(button.classes()).toContain('-start-11');
    wrapper.unmount();
  });

  it.each([
    'a',
    'button',
    'img',
    'audio',
    'video',
    'input',
    'pre',
    'code',
    'span role="button"',
  ])('does not reply on interactive %s', async tag => {
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = render();
    const surface = wrapper.get('[data-reply-surface]');
    const target = document.createElement(tag.split(' ')[0]);
    if (tag.includes('role')) target.setAttribute('role', 'button');
    surface.element.appendChild(target);
    target.dispatchEvent(
      new MouseEvent('dblclick', { bubbles: true, button: 0 })
    );
    expect(emit).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('replies once through the actual touch bindings and restores the surface', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = render();
    const surface = wrapper.get('[data-reply-surface]');
    await surface.trigger('touchstart', {
      touches: [{ clientX: 0, clientY: 0 }],
    });
    await surface.trigger('touchmove', {
      touches: [{ clientX: 64, clientY: 4 }],
    });
    expect(surface.classes()).toContain('translate-x-16');
    await surface.trigger('touchend');
    expect(surface.classes()).toContain('translate-x-0');
    expect(emit).toHaveBeenCalledExactlyOnceWith(
      BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE,
      expect.objectContaining({ id: 1 })
    );
    wrapper.unmount();
  });

  it('ignores non-left double clicks and preserves a code selection', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = render();
    document.body.appendChild(wrapper.element);
    const surface = wrapper.get('[data-reply-surface]');
    await surface.trigger('dblclick', { button: 2 });
    const code = document.createElement('code');
    code.textContent = 'selected code';
    surface.element.appendChild(code);
    const range = document.createRange();
    range.selectNodeContents(code);
    const selection = window.getSelection();
    selection.addRange(range);
    await surface.trigger('dblclick', { button: 0 });
    expect(emit).not.toHaveBeenCalled();
    expect(selection.toString()).toBe('selected code');
    selection.removeAllRanges();
    wrapper.unmount();
  });

  it('keeps reply and email labels available in en/es', () => {
    expect(en.CONVERSATION.REPLYBOX.REPLY).toBe('Reply');
    expect(es.CONVERSATION.REPLYBOX.REPLY).toBe('Responder');
    expect(en.EMAIL_HEADER.COLLAPSE).toBe('Collapse email');
    expect(es.EMAIL_HEADER.COLLAPSE).toBe('Contraer email');
    expect(Object.keys(en.EMAIL_HEADER).sort()).toEqual(
      Object.keys(es.EMAIL_HEADER).sort()
    );
  });
  it('keeps only the last message highlighted and holds reduced-motion feedback for 1600ms', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('matchMedia', () => ({ matches: true }));
    const first = render({ id: 1 });
    const second = render({ id: 2, private: true });
    emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId: 1 });
    await vi.advanceTimersByTimeAsync(20);
    emitter.emit(BUS_EVENTS.HIGHLIGHT_MESSAGE, { messageId: 2 });
    await vi.advanceTimersByTimeAsync(200);
    await nextTick();
    expect(first.get('[data-reply-surface]').classes()).toContain(
      'after:opacity-0'
    );
    expect(second.get('[data-reply-surface]').classes()).toContain(
      'after:opacity-100'
    );
    await vi.advanceTimersByTimeAsync(1600);
    expect(second.get('[data-reply-surface]').classes()).toContain(
      'after:opacity-0'
    );
    first.unmount();
    second.unmount();
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });
});
