import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';
import ReplyToMessage from '../ReplyToMessage.vue';

const options = (message, locale = 'en') => ({
  props: { message },
  global: {
    plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
    directives: {
      dompurifyHtml: (el, binding) => {
        el.innerHTML = binding.value;
      },
    },
  },
});

describe('composer reply quote', () => {
  it('reuses the bubble quote, author and two-line excerpt across the composer width', () => {
    const wrapper = mount(
      ReplyToMessage,
      options({ id: 1, sender: { name: 'Ana' }, content: '**Thank you**' })
    );
    expect(wrapper.classes()).toContain('w-full');
    expect(wrapper.classes()).toContain('relative');
    expect(wrapper.classes()).toContain('rounded-t-2xl');
    expect(
      wrapper
        .get(
          'button[aria-label="' + en.CONVERSATION.REPLYBOX.DISMISS_REPLY + '"]'
        )
        .classes()
    ).toEqual(expect.arrayContaining(['absolute', 'top-2', 'end-2']));
    const quote = wrapper.getComponent({ name: 'ReplyPreview' });
    expect(quote.props('composer')).toBe(true);
    expect(quote.classes()).toContain('before:bg-n-brand');
    expect(quote.classes()).toContain('before:w-[3px]');
    expect(quote.get('[class*="sm:line-clamp-2"]').text()).toBe('Thank you');
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
    expect(wrapper.get('[class*="sm:line-clamp-2"]').classes()).toContain(
      'line-clamp-1'
    );
    expect(wrapper.get('[class*="sm:line-clamp-2"]').classes()).toContain(
      'break-all'
    );
    expect(wrapper.getComponent({ name: 'ReplyPreview' }).classes()).toEqual(
      expect.arrayContaining(['w-full', '!pe-10', '!rounded-b-none'])
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
      expect(cancel.classes()).toContain('!size-6');
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
