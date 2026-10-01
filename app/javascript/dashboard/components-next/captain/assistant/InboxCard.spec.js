import { mount } from '@vue/test-utils';
import InboxCard from './InboxCard.vue';

const state = vi.hoisted(() => ({ isAdmin: true }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => state.isAdmin }),
}));

const mountCard = (props = {}) =>
  mount(InboxCard, {
    props: {
      id: 12,
      inbox: { id: 12, name: 'WhatsApp ventas', channel_type: 'Channel::Api' },
      ...props,
    },
    global: {
      directives: { onClickaway: {} },
      stubs: {
        CardLayout: { template: '<div><slot /></div>' },
        Policy: { template: '<div><slot /></div>' },
        DropdownMenu: true,
        Button: true,
      },
    },
  });

const switchButton = wrapper =>
  wrapper.get('[data-testid="inbox-appointments-switch"]');

describe('InboxCard appointments switch', () => {
  beforeEach(() => {
    state.isAdmin = true;
  });

  it('is hidden while the assistant has appointments off', () => {
    const wrapper = mountCard({ appointmentsAvailable: false });

    expect(wrapper.find('[data-testid="inbox-appointments"]').exists()).toBe(
      false
    );
  });

  it('shows the switch on by default when the assistant has appointments on', () => {
    const wrapper = mountCard({ appointmentsAvailable: true });

    expect(wrapper.text()).toContain('CAPTAIN.INBOXES.APPOINTMENTS.LABEL');
    expect(switchButton(wrapper).attributes('aria-checked')).toBe('true');
  });

  it('shows the switch off for an inbox that turned it off', () => {
    const wrapper = mountCard({
      appointmentsAvailable: true,
      inbox: { id: 12, name: 'Web', appointments_enabled: false },
    });

    expect(switchButton(wrapper).attributes('aria-checked')).toBe('false');
  });

  it('asks to switch it off and on', async () => {
    const wrapper = mountCard({ appointmentsAvailable: true });

    await switchButton(wrapper).trigger('click');

    expect(wrapper.emitted('toggleAppointments')).toEqual([
      [{ id: 12, value: false }],
    ]);
  });

  it('cannot be changed by someone who is not an administrator', () => {
    state.isAdmin = false;
    const wrapper = mountCard({ appointmentsAvailable: true });

    expect(switchButton(wrapper).attributes('disabled')).toBeDefined();
  });
});
