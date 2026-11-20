import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MessageError from '../MessageError.vue';
import enChatlist from 'dashboard/i18n/locale/en/chatlist.json';
import esChatlist from 'dashboard/i18n/locale/es/chatlist.json';

const messageCreatedAt = vi.hoisted(() => ({ value: null }));

vi.mock('../provider.js', () => ({
  useMessageContext: () => ({
    orientation: { value: 'left' },
    status: { value: 'failed' },
    createdAt: {
      value: messageCreatedAt.value ?? Math.floor(Date.now() / 1000),
    },
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
  afterEach(() => {
    messageCreatedAt.value = null;
  });

  it('keeps the retry action label in sync between English and Spanish', () => {
    expect(enChatlist.CHAT_LIST.RETRY).toBe('Retry');
    expect(esChatlist.CHAT_LIST.RETRY).toBe('Reintentar');
  });

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

  it('shows retry as text while the message is within the 24-hour window', async () => {
    const wrapper = render('es', '(#131000) Temporary Meta error');
    const retry = wrapper.get('button');
    expect(retry.text()).toBe('Reintentar');
    expect(retry.attributes('disabled')).toBeUndefined();
    await retry.trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
  });

  it('shows the template instruction and hides retry after the 24-hour window', () => {
    messageCreatedAt.value = Math.floor(Date.now() / 1000) - 25 * 60 * 60;
    const wrapper = render('en', '(#131047) Re-engagement message');
    expect(wrapper.text()).toContain(
      'Outside the 24-hour window: send a template'
    );
    expect(wrapper.find('button').exists()).toBe(false);
  });
});
