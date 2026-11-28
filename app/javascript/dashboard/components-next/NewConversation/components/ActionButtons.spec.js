import { shallowMount } from '@vue/test-utils';
import FileUpload from 'vue-upload-component';
import ActionButtons from './ActionButtons.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    fetchSignatureFlagFromUISettings: () => false,
    setSignatureFlagForInbox: vi.fn(),
    isEditorHotKeyEnabled: () => false,
  }),
}));
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: () => ({ onFileUpload: vi.fn() }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

describe('new email composer attachments', () => {
  it('enables file drops and provides the shared drop target', () => {
    const wrapper = shallowMount(ActionButtons, {
      props: { isEmailOrWebWidgetInbox: true },
      global: {
        stubs: {
          FileUpload: {
            props: ['drop', 'dropDirectory'],
            data: () => ({ dropActive: false }),
            template: '<div />',
          },
        },
      },
    });
    expect(wrapper.getComponent(FileUpload).props()).toMatchObject({
      drop: true,
      dropDirectory: false,
    });
    const overlay = wrapper.get('.fixed.inset-0');
    expect(overlay.isVisible()).toBe(false);
    expect(overlay.text()).toContain('CONVERSATION.REPLYBOX.DRAG_DROP');
    wrapper.unmount();
  });
});
