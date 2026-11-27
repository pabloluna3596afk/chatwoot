import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import WhatsappReferral from '../Text/WhatsappReferral.vue';

describe('WhatsApp referral surface', () => {
  it('uses an unbordered alpha surface suitable for the message bubble', () => {
    const wrapper = mount(WhatsappReferral, {
      props: { referral: { headline: 'Spring offer', body: 'A short offer' } },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: conversation },
          }),
        ],
      },
    });
    const card = wrapper.get('[data-testid="whatsapp-referral"]');
    expect(card.classes()).toContain('bg-n-alpha-black1');
    expect(card.classes()).not.toContain('border');
    expect(card.text()).toContain('Spring offer');
  });
});
