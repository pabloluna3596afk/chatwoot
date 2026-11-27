import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CitasContactData from '../CitasContactData.vue';
import activationEn from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import attributesEn from 'dashboard/i18n/locale/en/calendarAppointmentAttributes.json';
import typesEn from 'dashboard/i18n/locale/en/attributesMgmt.json';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('CitasContactData', () => {
  it('lists enabled attributes and copies the key with a fallback', async () => {
    const writeText = vi
      .fn()
      .mockRejectedValue(new Error('clipboard unavailable'));
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    document.execCommand = vi.fn(() => true);
    const wrapper = mount(CitasContactData, {
      props: {
        attributes: {
          enabled_keys: ['proxima_cita'],
          results: {},
        },
        expanded: true,
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: {
              en: { ...activationEn, ...attributesEn, ...typesEn },
            },
          }),
        ],
        stubs: { RouterLink: true },
      },
    });
    expect(wrapper.text()).toContain('Next appointment');
    expect(wrapper.text()).toContain('Aug 26, 2026, 14:30');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Copy'))
      .trigger('click');
    expect(writeText).toHaveBeenCalledWith('proxima_cita');
    expect(document.execCommand).toHaveBeenCalledWith('copy');
    expect(wrapper.text()).toContain('Copied');
  });
});
