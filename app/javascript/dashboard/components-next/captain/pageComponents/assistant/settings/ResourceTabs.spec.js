import { mount } from '@vue/test-utils';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const tabs = [
  { label: 'Flows', count: 0, showZero: true, index: 0 },
  {
    label: 'Templates',
    count: 2,
    attention: true,
    attentionLabel: 'Need your permission',
    index: 1,
  },
];

describe('Captain resource tab selector', () => {
  it('shows zero counts and an accessible attention indicator', () => {
    const wrapper = mount(TabBar, {
      props: { tabs, tabListLabel: 'Resources' },
    });
    expect(wrapper.get('[role="tablist"]').attributes('aria-label')).toBe(
      'Resources'
    );
    expect(wrapper.get('[role="tab"]').text()).toBe('Flows (0)');
    expect(
      wrapper.get('[aria-label="Need your permission"]').classes()
    ).toContain('bg-n-amber-9');
    expect(wrapper.get('[role="tab"]').attributes('tabindex')).toBe('0');
  });

  it.each([
    ['ArrowRight', 1],
    ['ArrowLeft', 1],
    ['End', 1],
    ['Home', 0],
  ])('supports %s on the shared selector', async (key, target) => {
    const wrapper = mount(TabBar, {
      props: { tabs, tabListLabel: 'Resources' },
    });
    await wrapper.get('[role="tab"]').trigger('keydown', { key });
    expect(wrapper.emitted('tabChanged')[0][0]).toEqual(tabs[target]);
    await wrapper.setProps({ initialActiveTab: target });
    expect(
      wrapper.findAll('[role="tab"]')[target].attributes('aria-selected')
    ).toBe('true');
  });

  it('keeps the previous zero-count behavior for existing callers', () => {
    const wrapper = mount(TabBar, {
      props: { tabs: [{ label: 'Inbox', count: 0 }] },
    });
    expect(wrapper.get('button').text()).toBe('Inbox');
  });
});
