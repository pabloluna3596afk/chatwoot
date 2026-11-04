import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AudioTranscription from './AudioTranscription.vue';
import en from 'dashboard/i18n/locale/en/generalSettings.json';
import es from 'dashboard/i18n/locale/es/generalSettings.json';

const mocks = vi.hoisted(() => ({
  currentAccount: null,
  updateAccount: vi.fn(),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: mocks.currentAccount,
    updateAccount: mocks.updateAccount,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('AudioTranscription', () => {
  const mountComponent = locale =>
    mount(AudioTranscription, {
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
        stubs: {
          SectionLayout: {
            props: ['title', 'description'],
            template:
              '<section><h2>{{ title }}</h2><p>{{ description }}</p><slot name="headerActions" /></section>',
          },
          Switch: { template: '<button />' },
        },
      },
    });

  beforeEach(() => {
    mocks.currentAccount = ref({ settings: { audio_transcriptions: false } });
    mocks.updateAccount.mockReset();
  });

  it.each([
    ['en', 'Each transcribed audio uses one internal AI action.'],
    [
      'es',
      'Cada audio transcrito se descuenta de tus acciones internas de IA.',
    ],
  ])('shows the usage note in %s', (locale, note) => {
    expect(mountComponent(locale).text()).toContain(note);
  });
});
