import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EnforceMfa from './EnforceMfa.vue';
import en from 'dashboard/i18n/locale/en/settings.json';
import es from 'dashboard/i18n/locale/es/settings.json';

const mocks = vi.hoisted(() => ({
  currentAccount: null,
  updateAccount: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: mocks.currentAccount,
    updateAccount: mocks.updateAccount,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.useAlert }));

describe('EnforceMfa', () => {
  const mountComponent = locale =>
    mount(EnforceMfa, {
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
        stubs: {
          SectionLayout: {
            props: ['title', 'description'],
            template:
              '<section><h2>{{ title }}</h2><p>{{ description }}</p><slot name="headerActions" /></section>',
          },
          Switch: {
            props: ['modelValue'],
            emits: ['update:modelValue', 'change'],
            template:
              '<button data-testid="switch" @click="$emit(\'update:modelValue\', !modelValue); $emit(\'change\')" />',
          },
        },
      },
    });

  beforeEach(() => {
    mocks.currentAccount = ref({ settings: { enforce_mfa: false } });
    mocks.updateAccount.mockReset().mockResolvedValue();
    mocks.useAlert.mockReset();
  });

  it.each([
    ['en', 'Require two-factor authentication'],
    ['es', 'Exigir autenticación de dos factores'],
  ])('shows the account setting in %s', (locale, title) => {
    expect(mountComponent(locale).text()).toContain(title);
  });

  it('persists the account setting when enabled', async () => {
    const wrapper = mountComponent('en');

    await wrapper.get('[data-testid="switch"]').trigger('click');
    await flushPromises();

    expect(mocks.updateAccount).toHaveBeenCalledWith({ enforce_mfa: true });
  });
});
