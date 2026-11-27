import { flushPromises, mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import Index from '../Index.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';

const mocks = vi.hoisted(() => ({
  admin: { value: true },
  dispatch: vi.fn(),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(7),
    isCloudFeatureEnabled: () => false,
  }),
}));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed: makeComputed } = await import('vue');
  return {
    useAdmin: () => ({ isAdmin: makeComputed(() => mocks.admin.value) }),
  };
});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getTemplateDrafts: vi.fn(),
    getActivationKit: vi.fn(),
    getAppointmentAttributes: vi.fn(),
  },
}));
vi.mock('dashboard/api/captain/assistant', () => ({
  default: { get: vi.fn() },
}));

const stepStub = name => ({
  name,
  inheritAttrs: false,
  props: [
    'expanded',
    'attributes',
    'loading',
    'error',
    'templateData',
    'templateState',
    'refresh',
    'connected',
    'disabled',
    'connections',
    'calendars',
    'calendarErrors',
    'calendarLoading',
    'assistants',
    'withoutCalendar',
  ],
  template: `<div data-testid="${name}" :data-expanded="expanded" />`,
});
const mountPage = async query => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: Index }],
  });
  await router.push({ path: '/', query });
  await router.isReady();
  const wrapper = mount(RouterView, {
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...en, SIDEBAR: { CITAS: 'Appointments' } }, es },
        }),
      ],
      stubs: {
        SettingsLayout: {
          template: '<main><slot name="header"/><slot name="body"/></main>',
        },
        BaseSettingsHeader: { template: '<header />' },
        CitasStepCalendar: stepStub('calendar-step'),
        CitasStepMessages: stepStub('messages-step'),
        CitasStepInvitation: stepStub('invitation-step'),
        CitasContactData: stepStub('contact-step'),
        RouterLink: true,
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
};

const keyPaths = (value, prefix = '') =>
  Object.entries(value)
    .flatMap(([key, nested]) => {
      const path = prefix ? `${prefix}.${key}` : key;
      return [
        path,
        ...(nested && typeof nested === 'object' ? keyPaths(nested, path) : []),
      ];
    })
    .sort();

describe('Citas screen', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.admin.value = true;
    mocks.dispatch.mockResolvedValue({ payload: [] });
    CalendarAPI.getTemplateDrafts.mockResolvedValue({
      data: { results: {}, prepared_language: null },
    });
    CalendarAPI.getActivationKit.mockResolvedValue({ data: {} });
    CalendarAPI.getAppointmentAttributes.mockResolvedValue({
      data: { enabled_keys: [], results: {} },
    });
  });

  it.each([
    ['calendarios', 'calendar-step'],
    ['mensajes', 'messages-step'],
    ['invitacion', 'invitation-step'],
  ])(
    'opens the %s step from a legacy query and clears it',
    async (tab, step) => {
      const { wrapper, router } = await mountPage({ tab });
      await flushPromises();
      expect(router.currentRoute.value.query.tab).toBeUndefined();
      expect(
        wrapper.get(`[data-testid="${step}"]`).attributes('data-expanded')
      ).toBe('true');
    }
  );

  it('renders four rows without vertical tabs by default', async () => {
    const { wrapper } = await mountPage({});
    expect(wrapper.find('nav').exists()).toBe(false);
    expect(
      wrapper.findAll('[data-testid$="-step"], [data-testid="contact-step"]')
    ).toHaveLength(4);
  });

  it('keeps the new Spanish and English screen keys in parity', () => {
    expect(keyPaths(en.CITAS_SCREEN)).toEqual(keyPaths(es.CITAS_SCREEN));
  });
});
