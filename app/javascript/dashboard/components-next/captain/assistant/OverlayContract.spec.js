import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Editor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AddNewScenariosDialog from './AddNewScenariosDialog.vue';
import AddNewRulesDialog from './AddNewRulesDialog.vue';
import { mockNativeDialog } from 'dashboard/helper/specs/mockNativeDialog';

vi.mock('@amplitude/analytics-browser', () => ({}));
vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: ref(false) }),
}));

beforeEach(() => {
  mockNativeDialog();
  const rect = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
  Range.prototype.getClientRects = () => [rect];
  Range.prototype.getBoundingClientRect = () => rect;
});
afterEach(() => vi.restoreAllMocks());

it.each([AddNewRulesDialog, AddNewScenariosDialog])(
  'keeps the Captain pilot on the shared named, scrolling Dialog',
  async Component => {
    const wrapper = mount(Component, {
      attachTo: document.body,
      props: { onAdd: vi.fn(), buttonLabel: 'Add rule' },
      global: {
        plugins: [
          createStore({
            getters: {
              'accounts/isRTL': () => false,
              getUISettings: () => ({}),
              'captainTools/getRecords': () => [
                {
                  id: 'availability',
                  title: 'Availability',
                  description: 'Calendar',
                },
              ],
            },
          }),
        ],
        stubs: { CopilotMenuBar: true },
      },
    });
    try {
      const trigger = wrapper.get('button');
      trigger.element.focus();
      await trigger.trigger('click');
      await flushPromises();
      const dialog = wrapper.getComponent(Dialog);
      const native = document.querySelector('dialog[open]');
      expect(native.getAttribute('aria-labelledby')).toBe(
        native.querySelector('h3').id
      );
      expect(dialog.props('bodyScroll')).toBe(true);
      expect(native.className).toContain('max-h-[90dvh]');
      expect(native.querySelector('form').className).toContain(
        'env(safe-area-inset-bottom)'
      );
      if (Component === AddNewScenariosDialog) {
        const editor = wrapper.getComponent(Editor);
        editor.vm.showToolsMenu = true;
        await flushPromises();
        expect(native.querySelector('[data-menu-popover]')).not.toBeNull();
        const escape = new KeyboardEvent('keydown', {
          key: 'Escape',
          bubbles: true,
          cancelable: true,
        });
        editor.get('[contenteditable]').element.dispatchEvent(escape);
        await flushPromises();
        expect(escape.defaultPrevented).toBe(true);
        expect(native.querySelector('[data-menu-popover]')).toBeNull();
        expect(native.open).toBe(true);
      }
      native.dispatchEvent(new Event('cancel', { cancelable: true }));
      await flushPromises();
      expect(native.open).toBe(false);
    } finally {
      wrapper.unmount();
    }
  }
);
