import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import Index from './Index.vue';

const mocks = vi.hoisted(() => ({
  accountId: 1,
  isFeatureEnabledonAccount: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    computed(() =>
      key === 'getCurrentAccountId'
        ? mocks.accountId
        : mocks.isFeatureEnabledonAccount
    ),
}));

describe('AI settings page', () => {
  beforeEach(() => {
    mocks.isFeatureEnabledonAccount.mockReset().mockReturnValue(true);
  });

  it('renders the existing audio transcription setting when Captain is enabled', () => {
    const wrapper = mount(Index, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          BaseSettingsHeader: true,
          AudioTranscription: {
            template: '<section data-testid="transcription" />',
          },
        },
      },
    });

    expect(wrapper.find('[data-testid="transcription"]').exists()).toBe(true);
  });

  it('hides the setting when Captain is not enabled', () => {
    mocks.isFeatureEnabledonAccount.mockReturnValue(false);

    const wrapper = mount(Index, {
      global: {
        mocks: { $t: key => key },
        stubs: { BaseSettingsHeader: true, AudioTranscription: true },
      },
    });

    expect(wrapper.findComponent({ name: 'AudioTranscription' }).exists()).toBe(
      false
    );
  });
});
