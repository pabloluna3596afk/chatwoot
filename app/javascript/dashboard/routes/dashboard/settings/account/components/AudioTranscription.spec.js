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
              '<section><h2>{{ title }}</h2><p>{{ description }}</p><slot name="headerActions" /><slot /></section>',
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
    [
      'en',
      'Transcription uses one internal AI action per started minute (minimum one).',
    ],
    [
      'es',
      'La transcripción consume una acción interna de IA por cada minuto iniciado (mínimo una).',
    ],
  ])('shows the usage note in %s', (locale, note) => {
    const wrapper = mountComponent(locale);

    expect(wrapper.text()).toContain(note);
    expect(wrapper.find('.i-lucide-sparkles').exists()).toBe(true);
  });
});
