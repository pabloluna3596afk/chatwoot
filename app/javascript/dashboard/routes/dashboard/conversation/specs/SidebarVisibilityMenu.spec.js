import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { nextTick } from 'vue';
import SidebarVisibilityMenu from '../SidebarVisibilityMenu.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Draggable from 'vuedraggable';
import {
  DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER,
  DEFAULT_CONVERSATION_SIDEBAR_VISIBLE_ITEMS,
} from 'dashboard/composables/useUISettings';
import en from 'dashboard/i18n/locale/en/conversation.json';
import es from 'dashboard/i18n/locale/es/conversation.json';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));

let wrapper;
let store;
const mountMenu = async (settings = {}, locale = 'en') => {
  store = createStore({
    state: { settings },
    getters: {
      getUISettings: state => state.settings,
      'integrations/getIntegration': () => () => ({ enabled: false }),
      'attributes/getAttributesByModel': () => type =>
        type === 'conversation_attribute'
          ? [{ category: 'Shipping' }, { category: 'Billing' }]
          : [],
    },
    mutations: {
      update: (state, value) => {
        state.settings = value;
      },
    },
    actions: {
      updateUISettings: ({ commit }, { uiSettings }) =>
        commit('update', uiSettings),
    },
  });
  config.global.plugins = [
    createI18n({
      legacy: false,
      locale,
      messages: { en, es },
      missingWarn: false,
      fallbackWarn: false,
    }),
  ];
  wrapper = mount(SidebarVisibilityMenu, {
    global: {
      plugins: [store],
      stubs: { teleport: true },
      directives: { tooltip: () => {} },
    },
  });
  await wrapper.get('button').trigger('click');
};

afterEach(() => wrapper?.unmount());

describe('SidebarVisibilityMenu', () => {
  it('starts expanded, persists folding without changing visibility, and reopens categories', async () => {
    await mountMenu();
    const toggle = wrapper.get('button[aria-expanded]');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.findAllComponents(Checkbox)).toHaveLength(12);
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(wrapper.findAllComponents(Checkbox)).toHaveLength(9);
    expect(
      store.state.settings.conversation_sidebar_menu_collapsed_sections
    ).toEqual(['conversation_info']);
    expect(
      store.state.settings.conversation_sidebar_visible_items
    ).toBeUndefined();
    await toggle.trigger('click');
    expect(wrapper.findAllComponents(Checkbox)).toHaveLength(12);
    await toggle.trigger('click');
    const settings = { ...store.state.settings };
    wrapper.unmount();
    await mountMenu(settings);
    expect(
      wrapper.get('button[aria-expanded]').attributes('aria-expanded')
    ).toBe('false');
  });

  it('uses shared checkboxes, updates the count including zero and shows the empty notice', async () => {
    await mountMenu({ conversation_sidebar_visible_items: ['macros'] });
    expect(wrapper.text()).toContain('1 visible');
    const checkbox = wrapper
      .findAllComponents(Checkbox)
      .find(item => item.props('modelValue'));
    await checkbox.get('input').setValue(false);
    expect(wrapper.text()).toContain('0 visible');
    expect(wrapper.text()).toContain('All sections are hidden');
    expect(store.state.settings.conversation_sidebar_visible_items).toEqual([]);
    await checkbox.get('input').setValue(true);
    expect(wrapper.text()).toContain('1 visible');
    expect(wrapper.text()).not.toContain('All sections are hidden');
  });

  it('toggles a category through the shared checkbox without hiding its parent', async () => {
    await mountMenu();
    const categories = wrapper.findAllComponents(Draggable)[1];
    await categories
      .findAllComponents(Checkbox)[0]
      .get('input')
      .setValue(false);
    expect(
      store.state.settings.conversation_sidebar_visible_categories
        .conversation_attribute
    ).not.toContain('system');
    expect(
      wrapper.get('button[aria-expanded]').attributes('aria-expanded')
    ).toBe('true');
    expect(wrapper.text()).toContain('9 visible');
  });

  it('resets section visibility, order, category preferences and folded groups', async () => {
    await mountMenu({
      conversation_sidebar_visible_items: [],
      conversation_sidebar_menu_collapsed_sections: ['conversation_info'],
      conversation_sidebar_items_order: [{ name: 'macros' }],
      conversation_sidebar_visible_categories: { conversation_attribute: [] },
      conversation_sidebar_category_order: {
        conversation_attribute: ['billing'],
      },
    });
    await wrapper.get('button[aria-label="Reset"]').trigger('click');
    expect(store.state.settings.conversation_sidebar_visible_items).toEqual([
      ...DEFAULT_CONVERSATION_SIDEBAR_VISIBLE_ITEMS,
    ]);
    expect(store.state.settings.conversation_sidebar_items_order).toEqual([
      ...DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER,
    ]);
    expect(
      store.state.settings.conversation_sidebar_visible_categories
    ).toEqual({});
    expect(store.state.settings.conversation_sidebar_category_order).toEqual(
      {}
    );
    expect(
      store.state.settings.conversation_sidebar_menu_collapsed_sections
    ).toEqual([]);
    expect(
      wrapper.get('button[aria-expanded]').attributes('aria-expanded')
    ).toBe('true');
    expect(wrapper.text()).toContain('9 visible');
  });

  it('saves dragged section and category order and keeps the menu open while dragging', async () => {
    await mountMenu();
    let [sections] = wrapper.findAllComponents(Draggable);
    sections.vm.$emit('start');
    await nextTick();
    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    [sections] = wrapper.findAllComponents(Draggable);
    const reordered = [...sections.props('modelValue')].reverse();
    sections.vm.$emit('update:modelValue', reordered);
    await nextTick();
    [sections] = wrapper.findAllComponents(Draggable);
    sections.vm.$emit('end');
    await nextTick();
    expect(
      store.state.settings.conversation_sidebar_items_order.slice(0, 9)
    ).toEqual(reordered);
    expect(
      store.state.settings.conversation_sidebar_items_order
        .slice(9)
        .map(item => item.name)
    ).toEqual(['linear_issues', 'calendar_events', 'shopify_orders']);
    const categories = wrapper.findAllComponents(Draggable)[1];
    categories.props('list').reverse();
    categories.vm.$emit('end');
    expect(
      store.state.settings.conversation_sidebar_category_order
        .conversation_attribute
    ).toEqual(['shipping', 'billing', 'system']);
  });

  it.each(['en', 'es'])(
    'keeps menu translation keys in parity (%s)',
    async locale => {
      expect(Object.keys(en.CONVERSATION.SIDEBAR.MENU).sort()).toEqual(
        Object.keys(es.CONVERSATION.SIDEBAR.MENU).sort()
      );
      await mountMenu({}, locale);
      expect(
        wrapper.get('button[aria-expanded]').attributes('aria-label')
      ).not.toContain('CONVERSATION.');
      const reset =
        locale === 'en' ? 'Reset' : es.CONVERSATION.SIDEBAR.MENU.RESET;
      expect(
        wrapper.get(`button[aria-label="${reset}"]`).attributes('title')
      ).toBe(reset);
    }
  );
});
