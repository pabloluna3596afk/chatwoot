import { mount } from '@vue/test-utils';
import ColumnSelector from './ColumnSelector.vue';

describe('ColumnSelector', () => {
  it('renders a pinned column and emits visibility changes', async () => {
    const wrapper = mount(ColumnSelector, {
      props: {
        items: [{ key: 'email', label: 'Email' }],
        visibleKeys: ['name', 'email'],
        pinnedColumn: { key: 'name', label: 'Name' },
      },
    });

    expect(wrapper.text()).toContain('Name');
    expect(wrapper.text()).toContain('Email');
    await wrapper.findAll('input[type="checkbox"]')[1].setValue(false);
    expect(wrapper.emitted('toggle')[0]).toEqual(['email', false]);
  });
});
