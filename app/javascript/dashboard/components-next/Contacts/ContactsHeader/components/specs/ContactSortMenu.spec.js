import { mount } from '@vue/test-utils';
import ContactSortMenu from '../ContactSortMenu.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ContactSortMenu', () => {
  it('uses the upstream anchored menu and keeps the panel inside the mobile edge', async () => {
    const wrapper = mount(ContactSortMenu, {
      props: { activeSort: 'last_activity_at', activeOrdering: '' },
      global: { mocks: { $t: key => key } },
    });

    await wrapper.get('button').trigger('click');

    const panel = wrapper.get('.absolute.top-full');
    expect(panel.classes()).toContain('ltr:right-0');
    expect(panel.classes()).toContain('w-72');
    expect(wrapper.findAllComponents(SelectMenu)).toHaveLength(2);
    expect(wrapper.html()).not.toContain('dialog');
  });
});
