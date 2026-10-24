vi.mock('dashboard/components-next/Editor/Editor.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('@amplitude/analytics-browser', () => ({}));
import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import AddNewRulesDialog from './AddNewRulesDialog.vue';
import AddNewRulesInput from './AddNewRulesInput.vue';
import AddNewScenariosDialog from './AddNewScenariosDialog.vue';
import RuleCard from './RuleCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ScenariosCard from './ScenariosCard.vue';

vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ formatMessage: text => text }),
}));
const stubs = { CardLayout: { template: '<div><slot /></div>' } };

describe.each([AddNewRulesDialog, AddNewRulesInput, AddNewScenariosDialog])(
  'Captain draft persistence',
  Component => {
    it('waits, suppresses duplicate submit and preserves the draft on failure', async () => {
      let finish;
      const onAdd = vi.fn(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const close = vi.fn();
      const wrapper = shallowMount(Component, {
        props: { onAdd, modelValue: 'Draft' },
        global: {
          stubs: {
            Dialog: {
              props: ['isLoading'],
              methods: { close, open: vi.fn() },
              template: '<div><slot /></div>',
            },
          },
        },
      });
      const vm = wrapper.vm;
      if (Component === AddNewScenariosDialog)
        Object.assign(vm.state, {
          title: 'Draft',
          description: 'Description',
          instruction: 'Instruction',
        });
      if (vm.togglePopover) vm.togglePopover(true);
      const first = vm.onClickAdd();
      await vm.onClickAdd();
      await nextTick();
      expect(onAdd).toHaveBeenCalledTimes(1);
      if (vm.onClickCancel) vm.onClickCancel();
      if (vm.showPopover !== undefined) expect(vm.showPopover).toBe(true);
      if (wrapper.findComponent(Dialog).exists()) {
        expect(wrapper.getComponent(Dialog).props('isLoading')).toBe(true);
        expect(close).not.toHaveBeenCalled();
      }
      finish(false);
      await first;
      expect(wrapper.emitted('update:modelValue')).toBeUndefined();
      if (vm.state) expect(vm.state.title).toBe('Draft');
      if (vm.showPopover !== undefined) expect(vm.showPopover).toBe(true);
      expect(close).not.toHaveBeenCalled();
      onAdd.mockResolvedValue(true);
      await vm.onClickAdd();
      if (wrapper.findComponent(Dialog).exists())
        expect(close).toHaveBeenCalledOnce();
      if (vm.state) expect(vm.state.title).toBe('');
      else expect(wrapper.emitted('update:modelValue')).toEqual([['']]);
      if (vm.showPopover !== undefined) expect(vm.showPopover).toBe(false);
      wrapper.unmount();
    });
  }
);

describe.each([RuleCard, ScenariosCard])(
  'Captain confirmed edit',
  Component => {
    it('keeps the editor and original content until persistence succeeds', async () => {
      let finish;
      const save = vi.fn(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const wrapper = shallowMount(Component, {
        props: {
          id: 1,
          content: 'Original',
          title: 'Original',
          description: 'Description',
          instruction: 'Instruction',
          onEdit: save,
          onUpdate: save,
        },
        global: { directives: { 'dompurify-html': {} }, stubs },
      });
      const vm = wrapper.vm;
      vm.startEdit();
      if (Component === RuleCard) vm.editedContent = 'Draft';
      else vm.state.title = 'Draft';
      const submit = () =>
        Component === RuleCard ? vm.saveEdit() : vm.onClickUpdate();
      const first = submit();
      await submit();
      expect(save).toHaveBeenCalledTimes(1);
      expect(vm.isEditing).toBe(true);
      finish(false);
      await first;
      expect(vm.isEditing).toBe(true);
      expect(wrapper.props(Component === RuleCard ? 'content' : 'title')).toBe(
        'Original'
      );
      save.mockResolvedValue(true);
      await submit();
      expect(vm.isEditing).toBe(false);
      wrapper.unmount();
    });
  }
);
