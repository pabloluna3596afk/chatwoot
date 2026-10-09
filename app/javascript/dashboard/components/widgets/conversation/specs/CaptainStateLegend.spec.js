import { mount } from '@vue/test-utils';
import CaptainStateLegend from '../CaptainStateLegend.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

describe('CaptainStateLegend', () => {
  const mountLegend = () =>
    mount(CaptainStateLegend, {
      global: {
        mocks: { $t: key => key },
        stubs: {
          NextButton: {
            template: '<button data-testid="captain-legend-toggle" />',
          },
        },
      },
    });

  it('hides the legend until the info button is clicked', async () => {
    const wrapper = mountLegend();
    expect(wrapper.find('[data-testid="captain-legend"]').exists()).toBe(false);

    await wrapper
      .find('[data-testid="captain-legend-toggle"]')
      .trigger('click');
    const legend = wrapper
      .getComponent(DropdownMenu)
      .find('[data-testid="captain-legend"]');

    expect(legend.exists()).toBe(true);
    expect(legend.findAll('li')).toHaveLength(3);
    expect(legend.text()).toContain('CHAT_LIST.CAPTAIN_LEGEND.TAKEN');
  });
});
