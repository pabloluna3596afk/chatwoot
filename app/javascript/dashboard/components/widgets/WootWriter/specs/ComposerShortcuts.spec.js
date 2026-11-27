import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Editor from '../Editor.vue';
import CannedResponse from '../../conversation/CannedResponse.vue';
import MacroList from '../../conversation/MacroList.vue';

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: false }),
}));
let view;
vi.mock('@chatwoot/prosemirror-schema', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    EditorView: class extends actual.EditorView {
      constructor(...args) {
        super(...args);
        view = this;
      }
    },
  };
});

const rect = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
let wrapper;
beforeEach(() => {
  Range.prototype.getClientRects = () => [rect];
  Range.prototype.getBoundingClientRect = () => rect;
  Element.prototype.scrollIntoView = () => {};
  wrapper = mount(Editor, {
    props: { enableMacros: true },
    attachTo: document.body,
    global: {
      plugins: [
        createStore({
          getters: {
            getUISettings: () => ({}),
            'globalConfig/get': () => ({}),
          },
        }),
      ],
      stubs: { CannedResponse: true, MacroList: true, CopilotMenuBar: true },
    },
  });
});
afterEach(() => {
  wrapper.unmount();
  vi.restoreAllMocks();
});

it('opens slash suggestions from text transactions without a desktop keydown and inserts once', async () => {
  view.dispatch(view.state.tr.insertText('/hello'));
  await flushPromises();
  const picker = wrapper.getComponent(CannedResponse);
  expect(picker.props('searchKey')).toBe('hello');
  picker.vm.$emit('replace', 'Hello there');
  await flushPromises();
  expect(view.state.doc.textContent).toBe('Hello there ');
  expect(wrapper.findComponent(CannedResponse).exists()).toBe(false);
  expect(document.activeElement).toBe(view.dom);
});

it('opens macros without a trigger, preserves the draft and closes after selection', async () => {
  view.dispatch(view.state.tr.insertText('Existing draft'));
  wrapper.vm.openMacros();
  await flushPromises();
  const macro = { id: 1, actions: [] };
  wrapper.getComponent(MacroList).vm.$emit('selectMacro', macro);
  await flushPromises();
  expect(wrapper.emitted('executeMacro')).toEqual([[macro]]);
  expect(view.state.doc.textContent).toBe('Existing draft');
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
});

it('closes the slash picker when opening macros and closes both before sending', async () => {
  view.dispatch(view.state.tr.insertText('/'));
  await flushPromises();
  wrapper.vm.openMacros();
  await flushPromises();
  expect(wrapper.findComponent(CannedResponse).exists()).toBe(false);
  expect(wrapper.findComponent(MacroList).exists()).toBe(true);
  wrapper.vm.closeComposerPickers();
  await flushPromises();
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
  expect(view.state.doc.textContent).toBe('/');
});

it('returns focus on dismissal and refuses the shortcut when disabled', async () => {
  wrapper.vm.openMacros();
  await flushPromises();
  wrapper.getComponent(MacroList).vm.$emit('close');
  await flushPromises();
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
  expect(document.activeElement).toBe(view.dom);
  await wrapper.setProps({ disabled: true });
  wrapper.vm.openMacros();
  await flushPromises();
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
});

it('closes a toolbar-opened macro picker on empty-search Backspace without deleting the draft', async () => {
  view.dispatch(view.state.tr.insertText('Keep this draft'));
  wrapper.vm.openMacros();
  await flushPromises();
  wrapper.getComponent(MacroList).vm.$emit('removeTrigger');
  await flushPromises();
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
  expect(view.state.doc.textContent).toBe('Keep this draft');
  expect(document.activeElement).toBe(view.dom);
});
