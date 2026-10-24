import { mount } from '@vue/test-utils';
import CardLayout from './CardLayout.vue';

describe('CardLayout padding compatibility', () => {
  it('preserves default layout, padding, click and after slot', async () => {
    const wrapper = mount(CardLayout, {
      slots: { default: 'Body', after: '<footer>After</footer>' },
    });
    const body = wrapper.findAll('div')[1];
    expect(body.classes()).toEqual(
      expect.arrayContaining(['px-6', 'py-5', 'flex-col'])
    );
    await body.trigger('click');
    expect(wrapper.emitted('click')).toHaveLength(1);
    expect(wrapper.get('footer').text()).toBe('After');
  });

  it('preserves selectable row padding', () => {
    const wrapper = mount(CardLayout, {
      props: { selectable: true, layout: 'row' },
    });
    expect(wrapper.findAll('div')[1].classes()).toEqual(
      expect.arrayContaining(['px-10', 'py-6', 'flex-row'])
    );
  });

  it('opts into compact padding', () => {
    const wrapper = mount(CardLayout, { props: { padding: 'compact' } });
    expect(wrapper.findAll('div')[1].classes()).toEqual(
      expect.arrayContaining(['px-4', 'py-4'])
    );
    expect(wrapper.findAll('div')[1].classes()).not.toContain('px-6');
  });
});
