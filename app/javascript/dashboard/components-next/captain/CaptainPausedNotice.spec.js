import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import CaptainPausedNotice from './CaptainPausedNotice.vue';

const state = vi.hoisted(() => ({
  assistants: [],
  user: { type: 'User' },
  isAdmin: true,
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { assistantId: '3' } }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter =>
    computed(() =>
      getter === 'captainAssistants/getRecords' ? state.assistants : state.user
    ),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ checkPermissions: () => state.isAdmin }),
}));

const mountNotice = () =>
  mount(CaptainPausedNotice, {
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a data-testid="captain-paused-billing-link"><slot /></a>',
        },
      },
    },
  });

const assistant = (overrides = {}) => ({
  id: 3,
  name: 'Asistente de Ventas',
  paused_reason: null,
  ...overrides,
});

describe('CaptainPausedNotice', () => {
  beforeEach(() => {
    state.assistants = [assistant()];
    state.user = { type: 'User' };
    state.isAdmin = true;
  });

  it('shows nothing while the assistant can answer', () => {
    expect(
      mountNotice().find('[data-testid="captain-paused-notice"]').exists()
    ).toBe(false);
  });

  it('names the assistant when the AI key is missing', () => {
    state.assistants = [assistant({ paused_reason: 'missing_key' })];
    const wrapper = mountNotice();

    expect(wrapper.get('[data-testid="captain-paused-message"]').text()).toBe(
      'CAPTAIN.PAUSED_NOTICE.MISSING_KEY {"name":"Asistente de Ventas"}'
    );
  });

  it('links a super admin to the key settings', () => {
    state.assistants = [assistant({ paused_reason: 'missing_key' })];
    state.user = { type: 'SuperAdmin' };
    const wrapper = mountNotice();

    expect(
      wrapper.get('[data-testid="captain-paused-key-link"]').attributes('href')
    ).toBe('/super_admin/app_config?config=captain');
    expect(
      wrapper.find('[data-testid="captain-paused-key-hint"]').exists()
    ).toBe(false);
  });

  it('tells other admins to ask the installation administrator', () => {
    state.assistants = [assistant({ paused_reason: 'missing_key' })];
    const wrapper = mountNotice();

    expect(
      wrapper.find('[data-testid="captain-paused-key-link"]').exists()
    ).toBe(false);
    expect(wrapper.get('[data-testid="captain-paused-key-hint"]').text()).toBe(
      'CAPTAIN.PAUSED_NOTICE.ASK_INSTALLATION_ADMIN'
    );
  });

  it('names the assistant and links to billing when the monthly responses ran out', () => {
    state.assistants = [assistant({ paused_reason: 'quota_exhausted' })];
    const wrapper = mountNotice();

    expect(wrapper.get('[data-testid="captain-paused-message"]').text()).toBe(
      'CAPTAIN.PAUSED_NOTICE.QUOTA_EXHAUSTED {"name":"Asistente de Ventas"}'
    );
    expect(
      wrapper.find('[data-testid="captain-paused-billing-link"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="captain-paused-key-link"]').exists()
    ).toBe(false);
  });

  it('is only for administrators', () => {
    state.assistants = [assistant({ paused_reason: 'missing_key' })];
    state.isAdmin = false;

    expect(
      mountNotice().find('[data-testid="captain-paused-notice"]').exists()
    ).toBe(false);
  });

  it('shows nothing for a page without a matching assistant', () => {
    state.assistants = [assistant({ id: 99, paused_reason: 'missing_key' })];

    expect(
      mountNotice().find('[data-testid="captain-paused-notice"]').exists()
    ).toBe(false);
  });
});
