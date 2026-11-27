import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import ReplyToMessage from '../ReplyToMessage.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const options = (message, locale = 'en') => ({
  props: { message },
  global: {
    plugins: [
      createI18n({ legacy: false, locale, messages: { en, es } }),
      createStore({
        getters: {
          'inboxes/getInbox': () => id =>
            ({ 1: { name: 'Support' }, 2: { name: 'Sales' } })[id],
        },
      }),
    ],
    directives: {
      dompurifyHtml: (el, binding) => {
        el.innerHTML = binding.value;
      },
    },
  },
});

describe('composer reply quote', () => {
  it.each([
    [
      {
        message_type: 1,
        sender: null,
        content_attributes: { external_echo: true },
      },
      'Support',
    ],
    [{ message_type: 3, sender: null }, 'Support'],
    [{ message_type: 1, sender: { id: 7, name: 'Agent' } }, 'You'],
    [{ message_type: 1, sender_id: 7 }, 'You'],
    [{ message_type: 1, sender: { id: 8, name: 'Luis' } }, 'Luis'],
    [{ message_type: 1, sender_name: 'Lucia' }, 'Lucia'],
    [{ message_type: 0, sender: { id: 7, name: 'Ana' } }, 'Ana'],
    [
      { message_type: 1, sender_id: 8 },
      en.CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR,
    ],
    [
      { message_type: 1, sender: {} },
      en.CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR,
    ],
    [
      { message_type: 0, sender: null },
      en.CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR,
    ],
    [
      { message_type: 1, private: true, sender: { id: 7, name: 'Agent' } },
      en.CONVERSATION.REPLYBOX.PRIVATE_NOTE,
    ],
  ])('resolves the composer author for %j as %s', async (message, expected) => {
    const mountOptions = options({ id: 1, content: 'Quoted text', ...message });
    const wrapper = mount(ReplyToMessage, {
      ...mountOptions,
      props: { ...mountOptions.props, inboxId: 1, currentUserId: 7 },
    });
    expect(wrapper.get('.font-semibold').text()).toBe(expected);
    if (message.message_type === 1 && !message.private) {
      expect(wrapper.get('.font-semibold').classes()).toContain(
        'text-n-teal-11'
      );
    }
    wrapper.unmount();
  });

  it('updates the composer author with its inbox and keeps the unknown fallback', async () => {
    const wrapper = mount(
      ReplyToMessage,
      options({ id: 1, message_type: 1, sender: null })
    );
    await wrapper.setProps({ inboxId: 1 });
    expect(wrapper.get('.font-semibold').text()).toBe('Support');
    await wrapper.setProps({ inboxId: 2 });
    expect(wrapper.get('.font-semibold').text()).toBe('Sales');
    await wrapper.setProps({ inboxId: 99 });
    expect(wrapper.get('.font-semibold').text()).toBe(
      en.CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR
    );
    await wrapper.setProps({ inboxId: null });
    expect(wrapper.get('.font-semibold').text()).toBe(
      en.CONVERSATION.REPLY_PREVIEW.UNKNOWN_AUTHOR
    );
    wrapper.unmount();
  });

  it('jumps from its body, keeps dismiss independent, and disables cross-conversation quotes', async () => {
    const emit = vi.spyOn(emitter, 'emit');
    const wrapper = mount(
      ReplyToMessage,
      options({ id: 12, conversation_id: 3, content: 'Original' })
    );
    await wrapper.setProps({ conversationId: 3 });
    await wrapper.getComponent({ name: 'ReplyPreview' }).trigger('click');
    expect(emit).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 12,
      conversationId: 3,
      source: 'reply',
    });
    emit.mockClear();
    await wrapper.get('button[aria-label="Dismiss reply"]').trigger('click');
    expect(emit).not.toHaveBeenCalled();
    expect(wrapper.emitted('dismiss')).toHaveLength(1);
    await wrapper.setProps({ conversationId: 4 });
    expect(
      wrapper.getComponent({ name: 'ReplyPreview' }).attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
    emit.mockRestore();
  });
  it('reuses the bubble quote, author and two-line excerpt across the composer width', () => {
    const wrapper = mount(
      ReplyToMessage,
      options({ id: 1, sender: { name: 'Ana' }, content: '**Thank you**' })
    );
    expect(wrapper.classes()).not.toContain('w-full');
    expect(wrapper.classes()).toContain('rounded-t-2xl');
    expect(wrapper.classes()).toContain('rounded-b-none');
    expect(wrapper.classes()).toContain('bg-n-alpha-1');
    expect(wrapper.classes()).not.toContain('m-2');
    expect(
      wrapper
        .get(
          'button[aria-label="' + en.CONVERSATION.REPLYBOX.DISMISS_REPLY + '"]'
        )
        .classes()
    ).toContain('w-12');
    const quote = wrapper.getComponent({ name: 'ReplyPreview' });
    expect(quote.props('composer')).toBe(true);
    expect(quote.classes()).toContain('bg-transparent');
    expect(quote.classes()).toContain('rounded-none');
    expect(quote.element.firstElementChild.classList).toContain(
      'bg-n-blue-9/70'
    );
    expect(quote.findAll('.line-clamp-1').at(-1).text()).toBe('Thank you');
    expect(quote.text()).toContain('Ana');
  });

  it('bounds long author names and excerpts without shrinking the quote for cancellation', () => {
    const wrapper = mount(
      ReplyToMessage,
      options({
        id: 1,
        sender: { name: 'Author'.repeat(100) },
        content: 'Text '.repeat(100),
      })
    );
    expect(wrapper.get('.line-clamp-1').classes()).toContain('break-all');
    const excerpt = wrapper.findAll('.line-clamp-1').at(-1);
    expect(excerpt.classes()).toContain('line-clamp-1');
    expect(excerpt.classes()).toContain('sm:line-clamp-2');
    expect(wrapper.getComponent({ name: 'ReplyPreview' }).classes()).toContain(
      'flex-1'
    );
  });

  it.each(['en', 'es'])(
    'shows an image thumbnail and accessible cancellation in %s',
    async locale => {
      const wrapper = mount(
        ReplyToMessage,
        options(
          {
            id: 1,
            attachments: [
              {
                file_type: 'image',
                data_url: '/photo.png',
                thumb_url: '/thumb.png',
              },
            ],
          },
          locale
        )
      );
      expect(wrapper.get('img').attributes('src')).toBe('/thumb.png');
      expect(wrapper.text()).toContain(locale === 'en' ? 'Photo' : 'Foto');
      const cancel = wrapper.get(
        'button[aria-label="' +
          (locale === 'en' ? en : es).CONVERSATION.REPLYBOX.DISMISS_REPLY +
          '"]'
      );
      expect(cancel.classes()).toContain('w-12');
      await cancel.trigger('click');
      expect(wrapper.emitted('dismiss')).toHaveLength(1);
    }
  );

  it.each(['audio', 'file'])(
    'shows the localized %s type without a thumbnail',
    type => {
      const wrapper = mount(
        ReplyToMessage,
        options({
          id: 1,
          attachments: [{ file_type: type, data_url: '/recording.mp3' }],
        })
      );
      expect(wrapper.text()).toContain(
        en.CONVERSATION.REPLY_PREVIEW[type.toUpperCase()]
      );
      expect(wrapper.find('img').exists()).toBe(false);
    }
  );

  it('updates its quote when the selected reply changes', async () => {
    const wrapper = mount(ReplyToMessage, options({ id: 1, content: 'First' }));
    await wrapper.setProps({ message: { id: 2, content: 'Second' } });
    expect(wrapper.text()).toContain('Second');
    expect(wrapper.text()).not.toContain('First');
  });
});
