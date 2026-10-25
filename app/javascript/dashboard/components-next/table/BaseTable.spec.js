import { mount } from '@vue/test-utils';
import BaseTable from './BaseTable.vue';

describe('BaseTable', () => {
  it('isolates a wide table in a local horizontal scroll container', () => {
    const wrapper = mount(BaseTable, {
      props: {
        headers: ['Name', 'Description'],
        items: [{ id: 1 }],
      },
      slots: { row: '<tr><td>Label</td><td>A long description</td></tr>' },
    });

    const scrollContainer = wrapper.get('[data-table-scroll]');
    expect(scrollContainer.classes()).toEqual(
      expect.arrayContaining(['min-w-0', 'max-w-full', 'overflow-x-auto'])
    );
    expect(scrollContainer.get('table').exists()).toBe(true);
    wrapper.unmount();
  });
});
