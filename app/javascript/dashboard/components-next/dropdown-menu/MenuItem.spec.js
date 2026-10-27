import { mount } from '@vue/test-utils';
import MenuItem from './MenuItem.vue';

describe('MenuItem', () => {
  it('aligns menu content to the start and keeps labels on one line', () => {
    const wrapper = mount(MenuItem, {
      slots: { default: '<span>Sort by activity</span>' },
    });

    expect(wrapper.classes()).toContain('justify-start');
    expect(wrapper.classes()).toContain('text-start');
    expect(wrapper.classes()).toContain('whitespace-nowrap');
    expect(wrapper.text()).toBe('Sort by activity');
  });

  it('emits click events', async () => {
    const wrapper = mount(MenuItem);
    await wrapper.trigger('click');
    expect(wrapper.emitted('click')).toHaveLength(1);
  });
});
