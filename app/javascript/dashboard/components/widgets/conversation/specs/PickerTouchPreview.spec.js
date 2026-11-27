import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import MacroList from '../MacroList.vue';
import CannedResponse from '../CannedResponse.vue';
import CannedResponsesPicker from '../CannedResponses/CannedResponsesPicker.vue';
import PreviewPicker from 'dashboard/components-next/preview-picker/PreviewPicker.vue';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';

vi.mock('dashboard/composables/useMacros', () => ({
  useMacros: () => ({ resolveMacroActions: () => [] }),
}));
const responses = [
  { id: 1, short_code: 'hello', content: 'Hello' },
  { id: 2, short_code: 'bye', content: 'Goodbye' },
];
const store = createStore({
  getters: {
    'accounts/isRTL': () => false,
    getUISettings: () => ({}),
    'macros/getUIFlags': () => ({}),
    'macros/getMacros': () => [
      { id: 1, name: 'Hello', actions: [] },
      { id: 2, name: 'Goodbye', actions: [] },
    ],
    getCannedResponses: () => responses,
    getUIFlags: () => ({}),
  },
  actions: { getCannedResponse: vi.fn() },
});
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it.each([
  [MacroList, false],
  [MacroList, true],
  [CannedResponse, false],
  [CannedResponse, true],
])(
  'shows search for %s with focusSearch=%s',
  async (component, focusSearch) => {
    const focus = vi.spyOn(HTMLInputElement.prototype, 'focus');
    wrapper = mount(component, {
      props: { focusSearch },
      attachTo: document.body,
      global: { plugins: [store] },
    });
    const card = wrapper.getComponent(PreviewPicker);
    if (focusSearch) {
      expect(document.activeElement).toBe(card.get('input').element);
      expect(focus).toHaveBeenCalledWith({ preventScroll: true });
      await card.get('input').setValue('Hello');
    } else {
      expect(card.find('input').exists()).toBe(false);
      expect(card.get('[role="status"]').text()).toContain('TYPE_TO_SEARCH');
      expect(focus).not.toHaveBeenCalledWith({ preventScroll: true });
      await wrapper.setProps({ searchKey: 'Hello' });
      expect(card.get('[role="status"]').text()).toBe('Hello');
    }
    await flushPromises();
    expect(card.findAll('[role="option"]')).toHaveLength(1);
  }
);

it.each([MacroList, CannedResponse])(
  'keeps the initial preview visible at 390px even with little height: %s',
  async component => {
    vi.stubGlobal('innerWidth', 390);
    vi.stubGlobal(
      'visualViewport',
      Object.assign(new EventTarget(), {
        width: 390,
        height: 300,
        offsetTop: 50,
        offsetLeft: 0,
      })
    );
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
      top: 270,
      bottom: 290,
      left: 16,
      right: 374,
      width: 358,
      height: 20,
    });
    wrapper = mount(component, { global: { plugins: [store] } });
    await flushPromises();
    const card = wrapper.getComponent(PreviewPicker);
    expect(card.props('previewLayout')).toBe('stacked');
    expect(card.element.style.maxHeight).toBe('196px');
    expect(card.element.style.height).toBe('196px');
    expect(card.element.style.width).toBe('358px');
    expect(card.find('.border-t').exists()).toBe(true);
    expect(card.get('[role="option"]').attributes('aria-selected')).toBe(
      'true'
    );
  }
);

it.each([MacroList, CannedResponse, CannedResponsesPicker])(
  'previews touch rows, ignores synthetic hover and confirms once: %s',
  async component => {
    wrapper = mount(component, {
      attachTo: document.body,
      global: { plugins: [store] },
    });
    const root =
      component === CannedResponsesPicker
        ? wrapper
        : wrapper.getComponent(PreviewPicker);
    const rows = root.findAll(
      component === CannedResponsesPicker
        ? 'button.text-start'
        : '[role="option"]'
    );
    const eventName = new Map([
      [MacroList, 'selectMacro'],
      [CannedResponse, 'replace'],
      [CannedResponsesPicker, 'onSelect'],
    ]).get(component);
    const input = document.activeElement;
    const expected =
      component === CannedResponsesPicker
        ? responses[1]
        : root.props('items')[1];
    await rows[0].trigger('pointerdown', { pointerType: 'touch' });
    await rows[0].trigger('click');
    expect(wrapper.emitted(eventName)).toBeUndefined();
    await rows[1].trigger('pointerdown', { pointerType: 'touch' });
    await rows[1].trigger('click');
    expect(wrapper.emitted(eventName)).toBeUndefined();
    await rows[0].trigger('mousemove');
    await rows[0].trigger('mouseenter');
    const use = root
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION.PICKER.USE');
    expect(use.classes()).toContain('min-h-11');
    await use.trigger('click');
    expect(wrapper.emitted(eventName)).toHaveLength(1);
    const result = wrapper.emitted(eventName)[0][0];
    if (component === CannedResponsesPicker) expect(result).toEqual(expected);
    if (component === MacroList) expect(result).toEqual(expected.macro);
    if (component === CannedResponse) expect(result).toEqual(expected.content);
    expect(document.activeElement).toBe(input);
  }
);

it.each([MacroList, CannedResponse, CannedResponsesPicker])(
  'confirms a second touch on the same row: %s',
  async component => {
    wrapper = mount(component, { global: { plugins: [store] } });
    const root =
      component === CannedResponsesPicker
        ? wrapper
        : wrapper.getComponent(PreviewPicker);
    const row = root.findAll(
      component === CannedResponsesPicker
        ? 'button.text-start'
        : '[role="option"]'
    )[1];
    const eventName = new Map([
      [MacroList, 'selectMacro'],
      [CannedResponse, 'replace'],
      [CannedResponsesPicker, 'onSelect'],
    ]).get(component);
    await row.trigger('pointerdown', { pointerType: 'touch' });
    await row.trigger('click');
    expect(wrapper.emitted(eventName)).toBeUndefined();
    await row.trigger('pointerdown', { pointerType: 'touch' });
    await row.trigger('click');
    expect(wrapper.emitted(eventName)).toHaveLength(1);
  }
);

it.each([MacroList, CannedResponse, CannedResponsesPicker])(
  'preserves mouse hover and single-click selection: %s',
  async component => {
    wrapper = mount(component, { global: { plugins: [store] } });
    const root =
      component === CannedResponsesPicker
        ? wrapper
        : wrapper.getComponent(PreviewPicker);
    const row = root.findAll(
      component === CannedResponsesPicker
        ? 'button.text-start'
        : '[role="option"]'
    )[1];
    const eventName = new Map([
      [MacroList, 'selectMacro'],
      [CannedResponse, 'replace'],
      [CannedResponsesPicker, 'onSelect'],
    ]).get(component);
    await row.trigger('pointermove', { pointerType: 'mouse' });
    await row.trigger('pointerdown', { pointerType: 'mouse' });
    await row.trigger('click');
    expect(wrapper.emitted(eventName)).toHaveLength(1);
  }
);

it.each([
  ['en', en, 'Type to search…', 'Use'],
  ['es', es, 'Escribe para buscar…', 'Usar'],
])(
  'translates the mirror and touch action in %s',
  async (locale, messages, placeholder, label) => {
    wrapper = mount(PreviewPicker, {
      props: {
        focusSearch: false,
        touchPreview: true,
        items: [{ id: 1, title: 'Hello' }],
      },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale,
            messages: { [locale]: messages },
          }),
        ],
      },
    });
    expect(wrapper.get('[role="status"]').text()).toBe(placeholder);
    await wrapper
      .get('[role="option"]')
      .trigger('pointerdown', { pointerType: 'touch' });
    await wrapper.get('[role="option"]').trigger('click');
    expect(
      wrapper.findAll('button').some(button => button.text() === label)
    ).toBe(true);
  }
);

it('focuses the toolbar canned search with preventScroll and filters its results', async () => {
  const focus = vi.spyOn(HTMLInputElement.prototype, 'focus');
  wrapper = mount(CannedResponsesPicker, {
    attachTo: document.body,
    global: { plugins: [store] },
  });
  const input = wrapper.get('input');
  expect(document.activeElement).toBe(input.element);
  expect(focus).toHaveBeenCalledWith({ preventScroll: true });
  await input.setValue('bye');
  expect(wrapper.findAll('button.text-start')).toHaveLength(1);
  expect(wrapper.get('button.text-start').text()).toContain('/bye');
});

it('does not select on a cancelled touch or scroll gesture', async () => {
  wrapper = mount(MacroList, { global: { plugins: [store] } });
  const card = wrapper.getComponent(PreviewPicker);
  const row = card.get('[role="option"]');
  await row.trigger('pointerdown', { pointerType: 'touch' });
  await row.trigger('pointermove', { pointerType: 'touch' });
  await row.trigger('pointercancel', { pointerType: 'touch' });
  expect(wrapper.emitted('selectMacro')).toBeUndefined();
  await row.trigger('pointerdown', { pointerType: 'touch' });
  await row.trigger('click');
  expect(wrapper.emitted('selectMacro')).toBeUndefined();
});

it.each([MacroList, CannedResponse])(
  'provides a touch-sized close button without changing focus: %s',
  async component => {
    wrapper = mount(component, {
      attachTo: document.body,
      global: { plugins: [store] },
    });
    const active = document.activeElement;
    const button = wrapper
      .getComponent(PreviewPicker)
      .get('button[aria-label="CONVERSATION.PICKER.CLOSE"]');
    expect(button.classes()).toContain('min-h-11');
    expect(button.classes()).toContain('min-w-11');
    await button.trigger('pointerdown', { pointerType: 'touch' });
    await button.trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(document.activeElement).toBe(active);
  }
);

it.each([390, 1024])(
  'anchors to the editor edge on mobile and preserves the desktop caret at %s px',
  async width => {
    vi.stubGlobal('innerWidth', width);
    wrapper = mount(MacroList, {
      props: { caretPosition: { top: 40, height: 20 } },
      global: { plugins: [store] },
    });
    const anchor = wrapper.get('.pointer-events-none');
    expect(anchor.element.style.top).toBe(width === 390 ? '0px' : '40px');
    expect(anchor.element.style.height).toBe(width === 390 ? '0px' : '20px');
    await wrapper.setProps({ caretPosition: { top: 80, height: 20 } });
    expect(anchor.element.style.top).toBe(width === 390 ? '0px' : '80px');
  }
);
