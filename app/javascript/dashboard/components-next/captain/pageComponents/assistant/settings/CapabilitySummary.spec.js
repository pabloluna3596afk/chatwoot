import { flushPromises, mount } from '@vue/test-utils';
import CapabilitySummary from './CapabilitySummary.vue';

const { show } = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: show }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: 2 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

const capabilities = {
  groups: [
    {
      id: 'whatsapp',
      connection: 'not_connected',
      connect_route: 'captain_assistants_inboxes_index',
      items: [
        { id: 'allowed_templates', status: 'not_connected' },
        { id: 'allowed_flows', status: 'not_connected' },
        { id: 'reengagement', status: 'not_connected' },
      ],
    },
    {
      id: 'calendar',
      connection: 'not_connected',
      connect_route: 'settings_integrations_calendars',
      items: [
        { id: 'booking', status: 'not_connected' },
        { id: 'appointment_reminders', status: 'not_connected' },
      ],
    },
    {
      id: 'none',
      connection: 'always',
      items: [{ id: 'nudge', status: 'ready' }],
    },
  ],
};
const mountSummary = assistant =>
  mount(CapabilitySummary, {
    props: { assistant },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
        Icon: { props: ['icon'], template: '<span :data-icon="icon" />' },
        Label: {
          props: ['label'],
          template: '<span><slot name="icon" />{{ label }}</span>',
        },
        CapabilityRow: {
          props: ['item'],
          template: '<li data-testid="capability-row">{{ item.id }}</li>',
        },
      },
    },
  });

describe('CapabilitySummary', () => {
  beforeEach(() => {
    show.mockReset();
    show.mockResolvedValue({ capabilities });
  });

  it('fetches the assistant on mount and renders its three groups and six rows', async () => {
    const wrapper = mountSummary({});
    await flushPromises();

    expect(show).toHaveBeenCalledWith('captainAssistants/show', 2);
    expect(wrapper.findAll('[data-testid="capability-group"]')).toHaveLength(3);
    expect(wrapper.findAll('[data-testid="capability-row"]')).toHaveLength(6);
    expect(wrapper.text()).toContain('CAPTAIN.ASSISTANTS.CAPABILITIES.COUNT');
  });

  it('shows the empty integration notice when WhatsApp and Calendar are disconnected', async () => {
    const wrapper = mountSummary({});
    await flushPromises();

    expect(
      wrapper.find('[data-testid="capabilities-nothing-connected"]').exists()
    ).toBe(true);
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.CAPABILITIES.NOTHING_CONNECTED.TITLE'
    );
  });

  it('renders nothing and does not fail when capabilities are absent', async () => {
    show.mockResolvedValue({});
    const wrapper = mountSummary({ capabilities: null });
    await flushPromises();

    expect(wrapper.find('[data-testid="capability-summary"]').exists()).toBe(
      false
    );
  });

  it('does not add price or free-message claims to the summary copy', async () => {
    const wrapper = mountSummary({});
    await flushPromises();
    const copy = wrapper.text().toLowerCase();

    expect(copy).not.toContain('gratis');
    expect(copy).not.toContain('sin costo');
    expect(copy).not.toContain('$');
  });
});
