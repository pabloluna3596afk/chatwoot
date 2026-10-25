import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { defineComponent, ref } from 'vue';
import Tabs from '../Tabs.vue';
import TabsItem from '../TabsItem.vue';

const i18n = createI18n({ legacy: false, locale: 'en', messages: { en: {} } });

const createTabs = () => {
  const Host = defineComponent({
    components: { Tabs, TabsItem },
    setup() {
      const index = ref(0);
      return { index };
    },
    template: `<Tabs :index="index" @change="index = $event">
      <TabsItem name="First" :index="0" />
      <TabsItem name="Unavailable" :index="1" disabled />
      <TabsItem name="Last" :index="2" />
    </Tabs>`,
  });
  return mount(Host, { global: { plugins: [i18n] } });
};

describe('Tabs keyboard behavior', () => {
  it('exposes tabs and activates the next enabled item with arrow keys', async () => {
    const wrapper = createTabs();
    const tabs = wrapper.findAll('[role="tab"]');

    expect(wrapper.get('[role="tablist"]').exists()).toBe(true);
    expect(tabs[0].attributes('aria-selected')).toBe('true');
    expect(tabs[0].attributes('tabindex')).toBe('0');
    expect(tabs[1].attributes('disabled')).toBeDefined();

    await tabs[0].trigger('keydown', { key: 'ArrowRight' });
    expect(tabs[2].attributes('aria-selected')).toBe('true');
    expect(tabs[2].attributes('tabindex')).toBe('0');
  });

  it('supports Home and End and reverses arrow direction in RTL', async () => {
    const wrapper = createTabs();
    const tabs = wrapper.findAll('[role="tab"]');

    await tabs[0].trigger('keydown', { key: 'End' });
    expect(tabs[2].attributes('aria-selected')).toBe('true');

    wrapper.get('[role="tablist"]').element.dir = 'rtl';
    await tabs[2].trigger('keydown', { key: 'ArrowRight' });
    expect(tabs[0].attributes('aria-selected')).toBe('true');

    await tabs[0].trigger('keydown', { key: 'Home' });
    expect(tabs[0].attributes('tabindex')).toBe('0');
  });

  it('does not intercept Tab so focus can leave the tablist', () => {
    const wrapper = createTabs();
    const event = new KeyboardEvent('keydown', {
      key: 'Tab',
      bubbles: true,
      cancelable: true,
    });

    wrapper.get('[role="tab"]').element.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(false);
    expect(wrapper.findAll('[role="tab"][tabindex="0"]')).toHaveLength(1);
  });
});
