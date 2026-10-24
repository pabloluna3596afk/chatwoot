import { mount } from '@vue/test-utils';
import BaseSettingsHeader from '../BaseSettingsHeader.vue';

vi.mock('dashboard/components/widgets/BackButton.vue', () => ({
  default: { template: '<button />' },
}));
vi.mock('dashboard/components/CustomBrandPolicyWrapper.vue', () => ({
  default: { template: '<div><slot /></div>' },
}));

describe('BaseSettingsHeader', () => {
  it('sizes direct and linked CTAs without sizing nested menu options', () => {
    const wrapper = mount(BaseSettingsHeader, {
      props: { title: 'Settings' },
      slots: {
        actions: `<button data-cta>Add</button>
          <a><button data-cta>Create</button></a>
          <div><button class="py-2" data-format>CSV</button></div>`,
      },
    });
    const actions = wrapper.get('[class*="flex-row-reverse"]');
    const selectors = actions
      .classes()
      .filter(name => name.endsWith(':!h-auto'))
      .map(name =>
        name
          .slice(1, name.indexOf(']'))
          .replaceAll('_', ' ')
          .replace('&', ':scope')
      );
    const sizedButtons = actions.element.querySelectorAll(selectors.join(','));
    expect([...sizedButtons]).toEqual(
      wrapper.findAll('[data-cta]').map(node => node.element)
    );
    expect(wrapper.get('[data-format]').classes()).toContain('py-2');
  });

  it.each(['Buscar agentes', 'Buscar macros', 'Buscar etiquetas'])(
    'preserves the search model for %s',
    async searchPlaceholder => {
      const wrapper = mount(BaseSettingsHeader, {
        props: { title: 'Settings', searchPlaceholder, searchQuery: 'initial' },
      });
      const input = wrapper.get('input[type="search"]');
      expect(input.attributes('aria-label')).toBe(searchPlaceholder);
      expect(input.element.value).toBe('initial');
      await input.setValue('María');
      expect(wrapper.emitted('update:searchQuery')).toEqual([['María']]);
      await input.setValue('');
      expect(wrapper.emitted('update:searchQuery')[1]).toEqual(['']);
      await wrapper.setProps({ searchQuery: 'updated' });
      expect(input.element.value).toBe('updated');
    }
  );

  it('keeps tabs, count and actions alongside search', async () => {
    const onClick = vi.fn();
    const wrapper = mount(BaseSettingsHeader, {
      props: { title: 'Settings', searchPlaceholder: 'Search' },
      slots: {
        tabs: '<button>All</button>',
        count: '<span>12 records</span>',
        actions: {
          template: '<button @click="onClick">Add</button>',
          setup: () => ({ onClick }),
        },
      },
    });
    expect(wrapper.find('input').exists()).toBe(true);
    expect(wrapper.text()).toContain('12 records');
    await wrapper.get('button:last-child').trigger('click');
    expect(onClick).toHaveBeenCalledOnce();
  });

  it('does not add a search field or toolbar when unused', () => {
    const wrapper = mount(BaseSettingsHeader, { props: { title: 'Settings' } });
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.get('h1').text()).toBe('Settings');
  });
});
