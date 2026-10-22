import { mount } from '@vue/test-utils';
import AppointmentOriginLogo from '../AppointmentOriginLogo.vue';

const mountLogo = origin =>
  mount(AppointmentOriginLogo, {
    props: { origin },
    global: {
      mocks: { $t: key => key },
      directives: { tooltip: () => {} },
      stubs: { ChannelIcon: true, Icon: true },
    },
  });

describe('AppointmentOriginLogo', () => {
  it('shows the channel logo for an appointment booked from a conversation', () => {
    const wrapper = mountLogo({
      type: 'conversation',
      channel_type: 'Channel::Whatsapp',
      inbox_name: 'Ventas',
    });
    expect(
      wrapper.find('[data-testid="appointment-origin-conversation"]').exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'ChannelIcon' }).exists()).toBe(true);
  });

  it('shows the CRM mark when there is no conversation', () => {
    const wrapper = mountLogo({ type: 'crm' });
    expect(
      wrapper.find('[data-testid="appointment-origin-crm"]').exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'ChannelIcon' }).exists()).toBe(false);
  });

  it('shows the Google logo for what only exists in the calendar', () => {
    const wrapper = mountLogo({ type: 'google' });
    expect(
      wrapper.find('[data-testid="appointment-origin-google"] img').exists()
    ).toBe(true);
  });

  it('renders nothing without an origin', () => {
    expect(mountLogo(null).html()).toBe('<!--v-if-->');
  });
});
