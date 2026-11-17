import { mount } from '@vue/test-utils';
import CapabilityRow from './CapabilityRow.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'captain_assistants_settings_messaging_index',
    params: { accountId: 1, assistantId: 2 },
  }),
  useRouter: () => ({ push }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      if (key.endsWith('COUNT_SUFFIX')) return `(${params.count})`;
      if (key.endsWith('ACTION_LABEL'))
        return `${params.action}: ${params.title}`;
      return key;
    },
  }),
}));

const item = (overrides = {}) => ({
  id: 'allowed_templates',
  kind: 'template',
  status: 'ready',
  reason: null,
  count: 3,
  configure_route: 'captain_assistants_settings_messaging_index',
  configure_anchor: 'messaging-templates',
  inboxes: [],
  ...overrides,
});
const mountRow = (capability, group = {}) =>
  mount(CapabilityRow, {
    props: {
      item: capability,
      group: { connect_route: 'captain_assistants_inboxes_index', ...group },
    },
    global: {
      mocks: {
        $t: key => key,
      },
      stubs: {
        Icon: {
          props: ['icon'],
          template: '<span :data-icon="icon" aria-hidden="true" />',
        },
        Label: {
          props: ['label', 'color'],
          template:
            '<span :data-color="color"><slot name="icon" />{{ label }}</span>',
        },
      },
    },
  });

describe('CapabilityRow', () => {
  beforeEach(() => push.mockReset());

  it.each([
    ['ready', 'teal', 'i-lucide-circle-check', 'configure'],
    ['needs_setup', 'amber', 'i-lucide-wrench', 'configure'],
    ['not_connected', 'blue', 'i-lucide-plug', 'connect'],
    ['off', 'slate', 'i-lucide-power-off', 'turn_on'],
  ])(
    'renders the %s state with an accessible action',
    (status, color, icon, action) => {
      const wrapper = mountRow(item({ status }));
      const label = wrapper.find('[data-color]');
      const button = wrapper.get('[data-testid="capability-action"]');

      expect(label.attributes('data-color')).toBe(color);
      expect(button.attributes('aria-label')).toContain(
        `CAPTAIN.ASSISTANTS.CAPABILITIES.ACTIONS.${action}`
      );
      expect(wrapper.html()).toContain(icon);
      expect(wrapper.find('[data-testid="capability-kind"]').exists()).toBe(
        status !== 'not_connected'
      );
    }
  );

  it('hides message kind when the inbox is not connected and replaces copy with a reason', () => {
    const wrapper = mountRow(
      item({ status: 'not_connected', reason: 'not_connected_whatsapp' })
    );

    expect(wrapper.text()).not.toContain(
      'CAPTAIN.ASSISTANTS.CAPABILITIES.KIND.template'
    );
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.CAPABILITIES.REASONS.not_connected_whatsapp'
    );
  });

  it('does not show a zero count and shows a positive count in the title', () => {
    expect(mountRow(item({ count: 0 })).text()).not.toContain('(0)');
    expect(mountRow(item({ count: 3 })).text()).toContain('(3)');
  });

  it('shows differing inbox states and their details when expanded', async () => {
    const wrapper = mountRow(
      item({
        inboxes: [
          { inbox_id: 1, inbox_name: 'Ventas', status: 'ready', reason: null },
          {
            inbox_id: 2,
            inbox_name: 'Soporte',
            status: 'needs_setup',
            reason: 'no_items',
          },
        ],
      })
    );
    const details = wrapper.get(
      'button[aria-controls="capability-inboxes-allowed_templates"]'
    );

    expect(details.attributes('aria-expanded')).toBe('false');
    expect(wrapper.text()).toContain(
      'CAPTAIN.ASSISTANTS.CAPABILITIES.INBOXES.SUMMARY'
    );
    await details.trigger('click');
    expect(
      wrapper
        .get('button[aria-controls="capability-inboxes-allowed_templates"]')
        .attributes('aria-expanded')
    ).toBe('true');
    expect(wrapper.text()).toContain('Ventas');
    expect(wrapper.text()).toContain('Soporte');
  });

  it('does not show inbox details when their states match', () => {
    const wrapper = mountRow(
      item({
        inboxes: [
          { inbox_id: 1, inbox_name: 'Ventas', status: 'ready', reason: null },
          { inbox_id: 2, inbox_name: 'Soporte', status: 'ready', reason: null },
        ],
      })
    );

    expect(
      wrapper.find('button[aria-controls^="capability-inboxes-"]').exists()
    ).toBe(false);
  });

  it('focuses the template switch instead of navigating when templates are off', async () => {
    const wrapper = mountRow(item({ status: 'off', reason: 'templates_off' }));
    await wrapper.get('[data-testid="capability-action"]').trigger('click');

    expect(wrapper.emitted('focusTemplatesToggle')).toHaveLength(1);
    expect(push).not.toHaveBeenCalled();
  });
});
