import { mount } from '@vue/test-utils';
import InboxCard from './InboxCard.vue';

const state = vi.hoisted(() => ({ isAdmin: true }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => state.isAdmin }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: 2 } }),
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
        RouterLink: {
          props: ['to'],
          template: '<a :href="to.name"><slot /></a>',
        },
      },
    },
  });

describe('InboxCard appointments status', () => {
  beforeEach(() => {
    state.isAdmin = true;
  });

  it('is hidden while the assistant has appointments off', () => {
    const wrapper = mountCard({ appointmentsAvailable: false });

    expect(wrapper.find('[data-testid="inbox-appointments"]').exists()).toBe(
      false
    );
  });

  it('shows the saved status and links to assistant settings', () => {
    const wrapper = mountCard({ appointmentsAvailable: true });

    expect(wrapper.text()).toContain('CAPTAIN.INBOXES.APPOINTMENTS.LABEL');
    expect(wrapper.text()).toContain('CAPTAIN.INBOXES.APPOINTMENTS.ENABLED');
    expect(wrapper.find('a').attributes('href')).toBe(
      'captain_assistants_settings_appointments_index'
    );
  });

  it('shows when appointments are off for this inbox', () => {
    const wrapper = mountCard({
      appointmentsAvailable: true,
      inbox: { id: 12, name: 'Web', appointments_enabled: false },
    });

    expect(wrapper.text()).toContain('CAPTAIN.INBOXES.APPOINTMENTS.DISABLED');
  });

  it('hides the settings link from someone who is not an administrator', () => {
    state.isAdmin = false;
    const wrapper = mountCard({ appointmentsAvailable: true });

    expect(wrapper.find('a').exists()).toBe(false);
  });
});
