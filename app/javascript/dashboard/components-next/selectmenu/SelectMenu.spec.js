import { mount } from '@vue/test-utils';
import SelectMenu from './SelectMenu.vue';

describe('SelectMenu', () => {
  it('sizes the trigger to its label and keeps the default trailing chevron', () => {
    const wrapper = mount(SelectMenu, {
      props: {
        modelValue: 'all',
        label: 'All states',
        options: [{ value: 'all', label: 'All states' }],
      },
    });

    expect(wrapper.get('button').classes()).toContain('!w-fit');
    expect(wrapper.get('button').classes()).toContain('max-w-40');
    expect(wrapper.get('button').text()).toBe('All states');
  });

  it('truncates long option labels in the upstream submenu style', async () => {
    const longLabel = 'Assigned agent with the most recent activity';
    const wrapper = mount(SelectMenu, {
      props: {
        modelValue: 'all',
        label: 'All states',
        options: [
          { value: 'all', label: 'All states' },
          { value: 'agent', label: longLabel },
        ],
      },
    });

    await wrapper.get('button').trigger('click');

    expect(wrapper.findAll('button')[2].text()).toBe(longLabel);
    expect(wrapper.findAll('button')[2].classes()).toContain('!justify-end');
    expect(wrapper.findAll('button')[2].text()).toBe(longLabel);
  });
});
