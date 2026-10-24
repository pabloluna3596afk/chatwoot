import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import AddNewRulesDialog from './AddNewRulesDialog.vue';
import AddNewScenariosDialog from './AddNewScenariosDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

vi.mock('@amplitude/analytics-browser', () => ({}));
vi.mock('dashboard/components-next/Editor/Editor.vue', () => ({
  default: { props: ['modelValue'], template: '<div />' },
}));

beforeEach(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

describe.each([AddNewRulesDialog, AddNewScenariosDialog])(
  'Captain add Dialog',
  Component => {
    it('keeps all fields on failure, blocks repeated submit, then clears only after success', async () => {
      let resolve;
      const onAdd = vi.fn(
        () =>
          new Promise(done => {
            resolve = done;
          })
      );
      const wrapper = mount(Component, {
        attachTo: document.body,
        props: { onAdd, modelValue: 'Draft rule', buttonLabel: 'Add rule' },
        global: {
          stubs: {
            TeleportWithDirection: { template: '<div><slot /></div>' },
            OnClickOutside: { template: '<div><slot /></div>' },
          },
          plugins: [
            createStore({ getters: { 'accounts/isRTL': () => false } }),
          ],
        },
      });
      try {
        await wrapper.get('button').trigger('click');
        const dialog = wrapper.getComponent(Dialog);
        expect(dialog.props('bodyScroll')).toBe(true);
        expect(dialog.get('dialog').attributes('open')).toBeDefined();
        if (Component === AddNewScenariosDialog) {
          wrapper
            .getComponent(Input)
            .vm.$emit('update:modelValue', 'Draft scenario');
          wrapper
            .getComponent(TextArea)
            .vm.$emit('update:modelValue', 'Description');
          wrapper
            .getComponent(Editor)
            .vm.$emit('update:modelValue', 'Instructions');
          await flushPromises();
        }
        await dialog.get('form').trigger('submit');
        await dialog.get('form').trigger('submit');
        expect(onAdd).toHaveBeenCalledOnce();
        await dialog.get('dialog').trigger('cancel');
        expect(dialog.get('dialog').attributes('open')).toBeDefined();
        resolve(false);
        await flushPromises();
        expect(dialog.get('dialog').attributes('open')).toBeDefined();
        if (Component === AddNewScenariosDialog) {
          expect(wrapper.getComponent(Input).props('modelValue')).toBe(
            'Draft scenario'
          );
          expect(wrapper.getComponent(TextArea).props('modelValue')).toBe(
            'Description'
          );
          expect(wrapper.getComponent(Editor).props('modelValue')).toBe(
            'Instructions'
          );
          expect(onAdd).toHaveBeenCalledWith({
            id: '',
            title: 'Draft scenario',
            description: 'Description',
            instruction: 'Instructions',
          });
        } else {
          expect(wrapper.emitted('update:modelValue')).toBeUndefined();
          expect(wrapper.getComponent(Input).props('modelValue')).toBe(
            'Draft rule'
          );
          expect(onAdd).toHaveBeenCalledWith('Draft rule');
        }
        onAdd.mockResolvedValue(true);
        await dialog.get('form').trigger('submit');
        await flushPromises();
        expect(dialog.get('dialog').attributes('open')).toBeUndefined();
      } finally {
        wrapper.unmount();
      }
    });

    it('retains drafts when the dialog is cancelled and reopened', async () => {
      const wrapper = mount(Component, {
        props: { onAdd: vi.fn(), modelValue: 'Retained draft' },
        global: {
          stubs: {
            TeleportWithDirection: { template: '<div><slot /></div>' },
            OnClickOutside: { template: '<div><slot /></div>' },
          },
          plugins: [
            createStore({ getters: { 'accounts/isRTL': () => false } }),
          ],
        },
      });
      try {
        await wrapper.get('button').trigger('click');
        if (Component === AddNewScenariosDialog) {
          wrapper
            .getComponent(Input)
            .vm.$emit('update:modelValue', 'Retained draft');
          await flushPromises();
        }
        await wrapper
          .getComponent(Dialog)
          .get('button[type=button]')
          .trigger('click');
        await wrapper.get('button').trigger('click');
        expect(wrapper.getComponent(Input).props('modelValue')).toBe(
          'Retained draft'
        );
      } finally {
        wrapper.unmount();
      }
    });
  }
);
