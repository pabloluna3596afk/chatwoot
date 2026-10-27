import { ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import CopilotLauncher from './CopilotLauncher.vue';

const testState = vi.hoisted(() => ({
  uiSettings: null,
}));

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: createRef } = await import('vue');
  const uiSettings = createRef({ is_copilot_panel_open: false });
  testState.uiSettings = uiSettings;

  return {
    useUISettings: () => ({
      uiSettings,
      updateUISettings: settings => Object.assign(uiSettings.value, settings),
    }),
  };
});

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    ref(key === 'accounts/isFeatureEnabledonAccount' ? () => true : 1),
}));

describe('CopilotLauncher', () => {
  it('opens the floating panel from a dashboard view', async () => {
    const wrapper = mount(CopilotLauncher, {
      global: {
        stubs: {
          Button: {
            emits: ['click'],
            template:
              '<button aria-label="Open Copilot" @click="$emit(\'click\')" />',
          },
          ButtonGroup: { template: '<div><slot /></div>' },
        },
      },
    });

    await wrapper.get('#copilot-launcher-button').trigger('click');
    await nextTick();

    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(true);
    expect(wrapper.find('button').exists()).toBe(false);
  });
});
