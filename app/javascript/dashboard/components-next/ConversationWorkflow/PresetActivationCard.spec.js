import { mount } from '@vue/test-utils';
import PresetActivationCard from './PresetActivationCard.vue';

describe('PresetActivationCard', () => {
  it('passes activation intent through the shared card and preserves meta content', async () => {
    const wrapper = mount(PresetActivationCard, {
      props: {
        id: 'post_compra_n_dias',
        title: 'After a purchase',
        description: 'Follow up with the customer.',
        actionLabel: 'Activate example',
      },
      slots: { meta: '<p>Requires an order event</p>' },
    });

    expect(wrapper.text()).toContain('Requires an order event');
    await wrapper.get('button').trigger('click');

    expect(wrapper.emitted('apply')).toEqual([['post_compra_n_dias']]);
  });
});
