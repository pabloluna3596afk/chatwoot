import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AudioTranscriptionPreference from './AudioTranscriptionPreference.vue';
import en from 'dashboard/i18n/locale/en/settings.json';
import es from 'dashboard/i18n/locale/es/settings.json';

const mocks = vi.hoisted(() => ({
  currentAccount: null,
  uiSettings: null,
  updateUISettings: vi.fn(),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: mocks.currentAccount }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: mocks.uiSettings,
    updateUISettings: mocks.updateUISettings,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

describe('AudioTranscriptionPreference', () => {
  const mountComponent = locale =>
    mount(AudioTranscriptionPreference, {
      global: {
        plugins: [createI18n({ legacy: false, locale, messages: { en, es } })],
        stubs: {
          Switch: {
            props: ['modelValue', 'disabled'],
            emits: ['update:modelValue', 'change'],
            template:
              '<button :disabled="disabled" @click="$emit(\'update:modelValue\', true); $emit(\'change\')" />',
          },
        },
      },
    });

  beforeEach(() => {
    mocks.currentAccount = ref({ settings: { audio_transcriptions: false } });
    mocks.uiSettings = ref({});
    mocks.updateUISettings.mockReset();
  });

  it.each([
    ['en', 'The account administrator must enable audio transcription.'],
    [
      'es',
      'El administrador de la cuenta debe activar la transcripción de audio',
    ],
  ])(
    'shows the disabled reason in %s when the account feature is off',
    (locale, reason) => {
      const wrapper = mountComponent(locale);

      expect(wrapper.get('button').attributes('disabled')).toBeDefined();
      expect(wrapper.text()).toContain(reason);
    }
  );

  it('keeps the switch enabled when the account feature is on and saves the agent preference', async () => {
    mocks.currentAccount.value.settings.audio_transcriptions = true;
    const wrapper = mountComponent('en');

    expect(wrapper.get('button').attributes('disabled')).toBeUndefined();
    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(mocks.updateUISettings).toHaveBeenCalledWith({
      auto_transcribe_audio: true,
    });
  });
});
