import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Editor from '../Editor.vue';
import MacroList from '../../conversation/MacroList.vue';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';

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
          actions: { getCannedResponse: vi.fn() },
          getters: {
            getUISettings: () => ({}),
            'globalConfig/get': () => ({}),
            'accounts/isRTL': () => false,
            'macros/getUIFlags': () => ({}),
            'macros/getMacros': () => [
              { id: 1, name: 'Greeting', actions: [] },
              { id: 2, name: 'Closing', actions: [] },
            ],
            getUIFlags: () => ({}),
            getCannedResponses: () => [
              { id: 1, short_code: 'hello', content: 'Hello there' },
              { id: 2, short_code: 'bye', content: 'Goodbye' },
            ],
          },
        }),
      ],
      stubs: { CopilotMenuBar: true },
    },
  });
});
afterEach(() => {
  wrapper.unmount();
  vi.restoreAllMocks();
});

it.each(['#', '/'])(
  'keeps focus in the editor while typing %s and filtering',
  async trigger => {
    const focus = vi.spyOn(HTMLInputElement.prototype, 'focus');
    view.dispatch(view.state.tr.insertText(trigger));
    await flushPromises();
    expect(document.activeElement).toBe(view.dom);
    expect(focus).not.toHaveBeenCalled();
    expect(document.querySelector('[role="status"]').textContent).toContain(
      'CONVERSATION.PICKER.TYPE_TO_SEARCH'
    );
    expect(document.querySelector('input[role="combobox"]')).toBeNull();
    const mirrorDown = new Event('pointerdown', {
      bubbles: true,
      cancelable: true,
    });
    document.querySelector('[role="status"]').dispatchEvent(mirrorDown);
    expect(mirrorDown.defaultPrevented).toBe(true);
    view.dispatch(view.state.tr.insertText(trigger === '#' ? 'Clos' : 'hello'));
    await flushPromises();
    expect(document.querySelector('[role="status"]').textContent).toContain(
      trigger === '#' ? 'Clos' : 'hello'
    );
    const rows = document.querySelectorAll('[role="option"]');
    expect(rows).toHaveLength(1);
    expect(wrapper.getComponent(CaretAnchoredPicker).props('items')[0].id).toBe(
      trigger === '#' ? 2 : 1
    );
    expect(document.activeElement).toBe(view.dom);
  }
);

it.each(['#', '/'])(
  'selects once with Enter from %s without moving the editor cursor',
  async trigger => {
    view.dispatch(view.state.tr.insertText(trigger));
    await flushPromises();
    view.dom.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'ArrowDown',
        code: 'ArrowDown',
        bubbles: true,
        cancelable: true,
      })
    );
    view.dom.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Enter',
        code: 'Enter',
        keyCode: 13,
        bubbles: true,
        cancelable: true,
      })
    );
    await flushPromises();
    expect(view.state.doc.textContent).toBe(trigger === '#' ? '' : 'Goodbye ');
    if (trigger === '#')
      expect(wrapper.emitted('executeMacro')).toEqual([
        [{ id: 2, name: 'Closing', actions: [] }],
      ]);
    expect(document.activeElement).toBe(view.dom);
    expect(document.querySelector('[role="listbox"]')).toBeNull();
  }
);

it('dismisses with Escape without blurring the editor', async () => {
  view.dispatch(view.state.tr.insertText('#'));
  await flushPromises();
  const blur = vi.spyOn(view.dom, 'blur');
  view.dom.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'Escape',
      code: 'Escape',
      bubbles: true,
      cancelable: true,
    })
  );
  await flushPromises();
  expect(blur).not.toHaveBeenCalled();
  expect(document.activeElement).toBe(view.dom);
  expect(wrapper.findComponent(MacroList).exists()).toBe(false);
});

it('focuses toolbar search without scrolling and restores editor focus on close', async () => {
  const focus = vi.spyOn(HTMLInputElement.prototype, 'focus');
  wrapper.vm.openMacros();
  await flushPromises();
  const input = document.querySelector('input[role="combobox"]');
  expect(document.activeElement).toBe(input);
  expect(focus).toHaveBeenCalledWith({ preventScroll: true });
  input.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'Escape',
      code: 'Escape',
      bubbles: true,
      cancelable: true,
    })
  );
  await flushPromises();
  expect(document.activeElement).toBe(view.dom);
});

it.each([
  ['#', 'row'],
  ['/', 'row'],
  ['#', 'use'],
  ['/', 'use'],
])(
  'previews %s then selects with %s once without losing focus or leaving the trigger',
  async (trigger, confirm) => {
    view.dispatch(view.state.tr.insertText(trigger));
    await flushPromises();
    const row = document.querySelector('[role="option"]');
    const down = new Event('pointerdown', { bubbles: true, cancelable: true });
    Object.defineProperty(down, 'pointerType', { value: 'touch' });
    row.dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);
    row.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await flushPromises();
    expect(view.state.doc.textContent).toBe(trigger);
    expect(wrapper.emitted('executeMacro')).toBeUndefined();
    expect(document.activeElement).toBe(view.dom);
    const target =
      confirm === 'row'
        ? row
        : Array.from(
            document.querySelectorAll('[data-popover-content] button')
          ).find(button =>
            button.textContent.includes('CONVERSATION.PICKER.USE')
          );
    target.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await flushPromises();
    expect(document.querySelector('[role="listbox"]')).toBeNull();
    expect(document.activeElement).toBe(view.dom);
    expect(view.state.doc.textContent).toBe(
      trigger === '#' ? '' : 'Hello there '
    );
    if (trigger === '#')
      expect(wrapper.emitted('executeMacro')).toHaveLength(1);
  }
);

it('does not select on IME confirmation', async () => {
  view.dispatch(view.state.tr.insertText('#'));
  await flushPromises();
  view.dom.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      isComposing: true,
      bubbles: true,
    })
  );
  await flushPromises();
  expect(wrapper.emitted('executeMacro')).toBeUndefined();
  expect(wrapper.findComponent(MacroList).exists()).toBe(true);
});

it.each(['#', '/', 'toolbar'])(
  'closes %s with the visible button and restores editor focus',
  async trigger => {
    if (trigger === 'toolbar') wrapper.vm.openMacros();
    else view.dispatch(view.state.tr.insertText(trigger));
    await flushPromises();
    const button = document.querySelector(
      'button[aria-label="CONVERSATION.PICKER.CLOSE"]'
    );
    button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await flushPromises();
    expect(document.querySelector('[role="listbox"]')).toBeNull();
    expect(document.activeElement).toBe(view.dom);
    expect(wrapper.emitted('executeMacro')).toBeUndefined();
  }
);
