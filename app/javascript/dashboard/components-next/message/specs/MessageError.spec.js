import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MessageError from '../MessageError.vue';
import enChatlist from 'dashboard/i18n/locale/en/chatlist.json';
import esChatlist from 'dashboard/i18n/locale/es/chatlist.json';

vi.mock('../provider.js', () => ({
  useMessageContext: () => ({
    orientation: { value: 'left' },
    status: { value: 'failed' },
    createdAt: { value: Math.floor(Date.now() / 1000) },
    content: { value: 'Message' },
    attachments: { value: [] },
  }),
}));

const render = (locale, error) =>
  mount(MessageError, {
    props: { error, channelType: 'Channel::Whatsapp' },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: {
            en: { CHAT_LIST: enChatlist.CHAT_LIST },
            es: { CHAT_LIST: esChatlist.CHAT_LIST },
          },
        }),
      ],
      stubs: { Icon: true },
    },
  });

describe('MessageError', () => {
  it('keeps the short failed label visible and translates the tooltip reason before its code', () => {
    const raw = '(#131047) Re-engagement message';
    const wrapper = render('es', raw);

    expect(wrapper.find('span').text()).toBe('Error al enviar');
    expect(wrapper.find('.group').text()).toBe(
      'Fuera de la ventana de 24 horas: envía una plantilla (131047)'
    );
  });

  it('shows the original provider text without a prefix when its code has no translation', () => {
    const raw = '999999: Provider-specific reason';
    const wrapper = render('en', raw);

    expect(wrapper.find('span').text()).toBe('Failed to send');
    expect(wrapper.find('.group').text()).toBe(raw);
  });

  it('shows the original provider text when no code is present', () => {
    const raw = 'Provider-specific error';
    const wrapper = render('en', raw);

    expect(wrapper.find('.group').text()).toBe(raw);
  });
});
