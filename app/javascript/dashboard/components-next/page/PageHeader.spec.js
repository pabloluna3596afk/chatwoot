import { mount } from '@vue/test-utils';
import PageHeader from './PageHeader.vue';

describe('PageHeader', () => {
  it('renders the title prop and optional context and actions', () => {
    const wrapper = mount(PageHeader, {
      props: { title: 'Agents', description: 'Manage your agents' },
      slots: {
        moreInfo: '<a href="/help">More information</a>',
        actions: '<button>Add</button>',
        toolbar: '<input aria-label="Search" />',
      },
    });

    expect(wrapper.get('h1').text()).toBe('Agents');
    expect(wrapper.text()).toContain('Manage your agents');
    expect(wrapper.get('a').text()).toBe('More information');
    expect(wrapper.get('button').text()).toBe('Add');
    expect(wrapper.get('input').attributes('aria-label')).toBe('Search');
  });

  it('allows the title slot to replace the title prop', () => {
    const wrapper = mount(PageHeader, {
      props: { title: 'Ignored' },
      slots: { title: '<h1>Slot title</h1>' },
    });

    expect(wrapper.get('h1').text()).toBe('Slot title');
  });
});
