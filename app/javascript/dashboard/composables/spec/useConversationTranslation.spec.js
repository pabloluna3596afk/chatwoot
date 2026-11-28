import { computed, reactive } from 'vue';
import { mount } from '@vue/test-utils';
import { useConversationTranslation } from '../useConversationTranslation';

const state = reactive({
  accountEnabled: true,
  controlEnabled: false,
  disabled: true,
});
vi.mock('../useAccount', () => ({
  useAccount: () => ({
    currentAccount: computed(() => ({
      id: 1,
      settings: { auto_translate: true },
    })),
  }),
}));
vi.mock('../store', () => ({
  useMapGetter: key =>
    computed(() => {
      if (key === 'getSelectedChat') {
        return {
          additional_attributes: { auto_translate_disabled: state.disabled },
        };
      }
      return (_, feature) =>
        feature === 'auto_translate'
          ? state.accountEnabled
          : state.controlEnabled;
    }),
}));

const render = () =>
  mount({
    setup: useConversationTranslation,
    template: '<div :data-enabled="enabled" :data-toggle="canToggle" />',
  });

describe('conversation translation eligibility', () => {
  beforeEach(() => {
    Object.assign(state, {
      accountEnabled: true,
      controlEnabled: false,
      disabled: true,
    });
  });

  it('ignores a stored conversation switch when the new feature is off', () => {
    const wrapper = render();
    expect(wrapper.attributes('data-enabled')).toBe('true');
    expect(wrapper.attributes('data-toggle')).toBe('false');
  });

  it('stops and resumes translation when the reactive conversation setting changes', async () => {
    state.controlEnabled = true;
    const wrapper = render();
    expect(wrapper.attributes('data-enabled')).toBe('false');
    expect(wrapper.attributes('data-toggle')).toBe('true');
    state.disabled = false;
    await wrapper.vm.$nextTick();
    expect(wrapper.attributes('data-enabled')).toBe('true');
  });

  it('never enables translation or its menu when the account feature is off', () => {
    state.accountEnabled = false;
    state.controlEnabled = true;
    state.disabled = false;
    const wrapper = render();
    expect(wrapper.attributes('data-enabled')).toBe('false');
    expect(wrapper.attributes('data-toggle')).toBe('false');
  });
});
