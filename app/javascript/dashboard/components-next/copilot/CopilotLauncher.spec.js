import { ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import CopilotLauncher from './CopilotLauncher.vue';

const testState = vi.hoisted(() => ({
  uiSettings: null,
}));

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: createRef } = await import('vue');
  const uiSettings = createRef({
    is_copilot_panel_open: false,
    is_contact_sidebar_open: false,
  });
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

vi.mock('dashboard/composables/useCopilotEntryPoints', async () => {
  const { computed: createComputed } = await import('vue');
  return {
    useCopilotEntryPoints: () => ({
      showCopilotLauncher: createComputed(() => true),
    }),
  };
});

describe('CopilotLauncher', () => {
  beforeEach(() => {
    testState.uiSettings.value = {
      is_copilot_panel_open: false,
      is_contact_sidebar_open: false,
    };
  });

  it('keeps the launcher visible to minimize the floating panel', async () => {
    const wrapper = mount(CopilotLauncher, {
      global: {
        stubs: {
          Transition: true,
          Button: {
            emits: ['click'],
            template:
              '<button aria-label="Open Copilot" @click="$emit(\'click\')"><slot name="icon" /></button>',
          },
          ButtonGroup: { template: '<div><slot /></div>' },
        },
      },
    });

    await wrapper.get('#copilot-launcher-button').trigger('click');
    await nextTick();

    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(true);
    expect(wrapper.find('button').exists()).toBe(true);
    expect(wrapper.find('i').classes()).toContain('i-lucide-chevron-down');
    await wrapper.get('#copilot-launcher-button').trigger('click');
    await nextTick();
    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(false);
    expect(wrapper.find('i').classes()).toContain('i-woot-captain');
  });

  it('opens above the contact panel without changing its state', async () => {
    testState.uiSettings.value.is_contact_sidebar_open = true;
    const wrapper = mount(CopilotLauncher, {
      global: {
        stubs: {
          Transition: true,
          Button: {
            emits: ['click'],
            template:
              '<button aria-label="Open Copilot" @click="$emit(\'click\')"><slot name="icon" /></button>',
          },
          ButtonGroup: { template: '<div><slot /></div>' },
        },
      },
    });

    const launcher = wrapper
      .get('#copilot-launcher-button')
      .element.closest('.fixed');
    await wrapper.get('#copilot-launcher-button').trigger('click');

    expect(testState.uiSettings.value).toMatchObject({
      is_copilot_panel_open: true,
      is_contact_sidebar_open: true,
    });
    await wrapper.get('#copilot-launcher-button').trigger('click');
    expect(testState.uiSettings.value).toMatchObject({
      is_copilot_panel_open: false,
      is_contact_sidebar_open: true,
    });
    expect(launcher.classList).toContain(
      'bottom-[calc(env(safe-area-inset-bottom)+1rem)]'
    );
    expect(launcher.classList).toContain('ltr:right-4');
  });

  it('preserves the unread count while minimizing the open panel', async () => {
    testState.uiSettings.value.copilot_unread_count = 2;
    testState.uiSettings.value.is_copilot_panel_open = true;
    const wrapper = mount(CopilotLauncher, {
      global: {
        stubs: {
          Transition: true,
          Button: {
            emits: ['click'],
            template:
              '<button aria-label="Open Copilot" @click="$emit(\'click\')"><slot name="icon" /></button>',
          },
          ButtonGroup: { template: '<div><slot /></div>' },
        },
      },
    });

    expect(wrapper.text()).toContain('2');
    await wrapper.get('#copilot-launcher-button').trigger('click');

    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(false);
    expect(wrapper.text()).toContain('2');
  });
});
