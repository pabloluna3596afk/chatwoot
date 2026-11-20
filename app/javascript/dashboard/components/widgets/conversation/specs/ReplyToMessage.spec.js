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
    const quote = wrapper.getComponent({ name: 'ReplyPreview' });
    expect(quote.props('composer')).toBe(true);
    expect(quote.classes()).toContain('border-n-brand');
    expect(quote.get('.line-clamp-2').text()).toBe('Thank you');
    expect(quote.text()).toContain('Ana');
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
