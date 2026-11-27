import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';
import PreviewPicker from 'dashboard/components-next/preview-picker/PreviewPicker.vue';
import MacroList from '../MacroList.vue';
import CannedResponsesPicker from '../CannedResponses/CannedResponsesPicker.vue';
import CannedResponsesModal from '../CannedResponses/CannedResponsesModal.vue';
import Modal from 'dashboard/components/Modal.vue';

vi.mock('dashboard/composables/useMacros', () => ({
  useMacros: () => ({ resolveMacroActions: () => [] }),
}));

let wrapper;
let viewport;
const store = createStore({
  getters: {
    'accounts/isRTL': () => false,
    getUISettings: () => ({}),
    'macros/getUIFlags': () => ({}),
    'macros/getMacros': () => [
      { id: 1, name: 'Greeting', actions: [] },
      { id: 2, name: 'Closing', actions: [] },
    ],
    getCannedResponses: () => [
      { id: 1, short_code: 'hello', content: 'Hello', category: 'Greetings' },
    ],
  },
  actions: { getCannedResponse: vi.fn() },
});
beforeEach(() => {
  viewport = Object.assign(new EventTarget(), {
    width: 390,
    height: 300,
    offsetTop: 50,
    offsetLeft: 0,
  });
  vi.stubGlobal('visualViewport', viewport);
  vi.stubGlobal('innerWidth', 390);
  vi.stubGlobal('innerHeight', 844);
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
    x: 16,
    y: 270,
    top: 270,
    bottom: 290,
    left: 16,
    right: 374,
    width: 358,
    height: 20,
  });
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it('fits above the caret inside the visual viewport and tracks keyboard resizing', async () => {
  wrapper = mount(CaretAnchoredPicker, {
    props: { items: [{ id: 1, title: 'Hello' }] },
    global: { plugins: [store], stubs: { Teleport: false } },
  });
  await flushPromises();
  expect(window.visualViewport).toBe(viewport);
  const card = wrapper.getComponent(PreviewPicker);
  expect(card.element.style.maxHeight).toBe('196px');
  expect(card.element.style.bottom).toBe('582px');
  viewport.offsetTop = 100;
  viewport.dispatchEvent(new Event('scroll'));
  await flushPromises();
  expect(card.element.style.maxHeight).toBe('146px');
  expect(card.element.style.bottom).toBe('582px');
});

it('bounds the menu when the keyboard covers the caret', async () => {
  viewport.height = 150;
  wrapper = mount(CaretAnchoredPicker, {
    props: { items: [{ id: 1, title: 'Hello' }] },
    global: { plugins: [store] },
  });
  await flushPromises();
  const card = wrapper.getComponent(PreviewPicker);
  expect(card.element.style.maxHeight).toBe('118px');
  expect(card.element.style.bottom).toBe('660px');
  expect(card.element.style.width).toBe('358px');
});

it('clamps the inline edge in RTL inside a horizontally shifted viewport', async () => {
  viewport.width = 300;
  viewport.offsetLeft = 20;
  wrapper = mount(CaretAnchoredPicker, {
    props: { items: [{ id: 1, title: 'Hello' }] },
    global: {
      plugins: [createStore({ getters: { 'accounts/isRTL': () => true } })],
    },
  });
  await flushPromises();
  const card = wrapper.getComponent(PreviewPicker);
  expect(card.element.style.width).toBe('268px');
  expect(card.element.style.insetInlineStart).toBe('86px');
  expect(card.element.closest('[dir]').getAttribute('dir')).toBe('rtl');
});

it('ignores IME confirmation and closes once on Escape or an outside tap', async () => {
  wrapper = mount(CaretAnchoredPicker, {
    props: { items: [{ id: 1, title: 'Hello' }] },
    global: { plugins: [store] },
    attachTo: document.body,
  });
  await flushPromises();
  const input = wrapper.getComponent(PreviewPicker).get('input');
  await input.trigger('keydown', {
    key: 'Enter',
    code: 'Enter',
    isComposing: true,
  });
  expect(wrapper.emitted('select')).toBeUndefined();
  await input.trigger('keydown', { key: 'Escape', code: 'Escape' });
  expect(wrapper.emitted('close')).toHaveLength(1);
  document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
  document.body.dispatchEvent(
    new MouseEvent('click', { bubbles: true, detail: 1 })
  );
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(2);
});

it('keeps focus on search while selecting once by touch-generated click', async () => {
  wrapper = mount(PreviewPicker, {
    props: { items: [{ id: 1, title: 'Hello' }], previewLayout: 'none' },
    attachTo: document.body,
  });
  const row = wrapper.get('[role="option"]');
  expect(row.classes()).toContain('min-h-11');
  expect(
    wrapper
      .get('[role="listbox"]')
      .element.parentElement.classList.contains('min-h-0')
  ).toBe(true);
  const event = new MouseEvent('mousedown', {
    bubbles: true,
    cancelable: true,
  });
  row.element.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
  await row.trigger('click');
  expect(wrapper.emitted('select')).toEqual([[0]]);
  expect(document.activeElement).toBe(wrapper.get('input').element);
});

it('updates macro results when the editor search changes', async () => {
  wrapper = mount(MacroList, {
    props: { searchKey: 'Greeting' },
    global: { plugins: [store], stubs: { CaretAnchoredPicker: true } },
  });
  await wrapper.setProps({ searchKey: 'Closing' });
  expect(
    wrapper
      .getComponent(CaretAnchoredPicker)
      .props('items')
      .map(item => item.id)
  ).toEqual([2]);
});

it('provides touch-sized category filters and bounded, wrapping canned results', () => {
  wrapper = mount(CannedResponsesPicker, { global: { plugins: [store] } });
  wrapper
    .findAll('button')
    .forEach(button => expect(button.classes()).toContain('min-h-11'));
  expect(wrapper.get('button.text-start').classes()).toContain('break-words');
  expect(wrapper.find('.overflow-y-auto').classes()).toContain('min-h-0');
});

it('focuses canned search and preserves it through filters and a single selection', async () => {
  wrapper = mount(CannedResponsesPicker, {
    global: { plugins: [store] },
    attachTo: document.body,
  });
  expect(document.activeElement).toBe(wrapper.get('input').element);
  const category = wrapper
    .findAll('button')
    .find(button => button.text() === 'Greetings');
  const down = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
  category.element.dispatchEvent(down);
  expect(down.defaultPrevented).toBe(true);
  await category.trigger('click');
  await wrapper.get('button.text-start').trigger('click');
  expect(wrapper.emitted('onSelect')).toHaveLength(1);
  expect(document.activeElement).toBe(wrapper.get('input').element);
});

it('bounds the canned modal with the app viewport and keeps its list shrinkable', () => {
  wrapper = mount(CannedResponsesModal, {
    props: { show: true },
    global: {
      plugins: [store],
      components: { WootModal: Modal },
      stubs: { WootModal: false, WootModalHeader: true },
    },
  });
  expect(wrapper.get('.modal-mask').classes()).toContain(
    '!h-[var(--app-height,100dvh)]'
  );
  expect(wrapper.get('.modal-mask').classes()).toContain(
    '[&>.modal-container]:flex-col'
  );
  expect(
    wrapper
      .getComponent(CannedResponsesPicker)
      .element.parentElement.classList.contains('min-h-0')
  ).toBe(true);
});

it.each(['Escape', 'backdrop'])(
  'dismisses the canned modal with %s',
  async method => {
    wrapper = mount(CannedResponsesModal, {
      props: { show: true },
      attachTo: document.body,
      global: {
        plugins: [store],
        components: { WootModal: Modal },
        stubs: { WootModal: false, WootModalHeader: true },
      },
    });
    if (method === 'Escape') {
      await wrapper
        .get('input')
        .trigger('keydown', { key: 'Escape', code: 'Escape' });
    } else {
      await wrapper.get('.modal-mask').trigger('mousedown');
      await wrapper.get('.modal-mask').trigger('mouseup');
    }
    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(wrapper.emitted('update:show')).toEqual([[false]]);
  }
);
