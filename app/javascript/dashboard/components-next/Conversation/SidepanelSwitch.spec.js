import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import SidepanelSwitch from './SidepanelSwitch.vue';

const testState = vi.hoisted(() => ({
  uiSettings: null,
}));

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref: createRef } = await import('vue');
  const uiSettings = createRef({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
  testState.uiSettings = uiSettings;

  return {
    useUISettings: () => ({
      uiSettings,
      updateUISettings: settings => Object.assign(uiSettings.value, settings),
    }),
  };
});

vi.mock('dashboard/composables/store', async () => {
  const { ref: createRef } = await import('vue');
  return {
    useMapGetter: key =>
      createRef(key === 'accounts/isFeatureEnabledonAccount' ? () => true : 1),
  };
});

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

describe('SidepanelSwitch', () => {
  it('opens, closes, and switches to the contact panel', async () => {
    const wrapper = mount(SidepanelSwitch, {
      global: {
        stubs: {
          Button: {
            props: ['ariaLabel', 'icon'],
            emits: ['click'],
            template:
              '<button :aria-label="ariaLabel" @click="$emit(\'click\')" />',
          },
          ButtonGroup: { template: '<div><slot /></div>' },
        },
      },
    });
    const contactButton = wrapper.get(
      'button[aria-label="CONVERSATION.SIDEBAR.CONTACT"]'
    );

    await contactButton.trigger('click');
    expect(testState.uiSettings.value.is_contact_sidebar_open).toBe(true);
    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(false);

    testState.uiSettings.value.is_contact_sidebar_open = false;
    await nextTick();
    await contactButton.trigger('click');
    testState.uiSettings.value.is_contact_sidebar_open = false;
    await nextTick();
    await wrapper
      .get('button[aria-label="CONVERSATION.SIDEBAR.COPILOT"]')
      .trigger('click');
    await nextTick();
    expect(testState.uiSettings.value.is_contact_sidebar_open).toBe(false);
    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(true);

    await wrapper
      .get('button[aria-label="CONVERSATION.SIDEBAR.CONTACT"]')
      .trigger('click');
    expect(testState.uiSettings.value.is_copilot_panel_open).toBe(false);
    expect(testState.uiSettings.value.is_contact_sidebar_open).toBe(true);
  });
});
