import { mount } from '@vue/test-utils';
import SelectMenu from './SelectMenu.vue';

describe('SelectMenu', () => {
  it('aligns the selected value left and places the chevron at the opposite edge', () => {
    const wrapper = mount(SelectMenu, {
      props: {
        modelValue: 'all',
        label: 'All states',
        options: [{ value: 'all', label: 'All states' }],
      },
    });

    expect(wrapper.get('button').classes()).toContain('justify-between');
    expect(wrapper.get('button').classes()).toContain('text-start');
    expect(wrapper.get('button').text()).toBe('All states');
  });

  it('keeps long option labels readable without truncation', async () => {
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
    expect(wrapper.findAll('button')[2].classes()).toContain(
      '[&_span]:whitespace-normal'
    );
    expect(wrapper.findAll('button')[2].classes()).not.toContain('truncate');
  });
});
