import { mount } from '@vue/test-utils';
import CampaignLayout from '../CampaignLayout.vue';

describe('CampaignLayout', () => {
  it('preserves the full title, action label and click event', async () => {
    const headerTitle = 'Campañas para clientes con seguimiento personalizado';
    const buttonLabel = 'Crear una campaña de seguimiento personalizado';
    const wrapper = mount(CampaignLayout, {
      props: { headerTitle, buttonLabel },
      slots: { default: '<p>Campaigns</p>' },
    });
    expect(wrapper.get('header').text()).toContain(headerTitle);
    expect(wrapper.get('button').text()).toBe(buttonLabel);
    expect(wrapper.get('button').classes()).toContain('[&>span]:text-start');
    expect(wrapper.get('button').classes()).toContain(
      'sm:[&>span]:text-center'
    );
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('click')).toHaveLength(1);
    expect(wrapper.get('main').text()).toBe('Campaigns');
  });

  it('keeps the full-width option', () => {
    const wrapper = mount(CampaignLayout, { props: { fullWidth: true } });
    expect(wrapper.get('main > div').classes()).toContain('max-w-full');
  });
});
