import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import Index from '../Index.vue';
import CalendarResources from '../CalendarResources.vue';
import CalendarTemplates from '../CalendarTemplates.vue';
import CalendarSummary from '../CalendarSummary.vue';
import calendarConnections from 'dashboard/store/modules/calendarConnections';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AssistantAPI from 'dashboard/api/captain/assistant';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';
import enTypes from 'dashboard/i18n/locale/en/attributesMgmt.json';
import esTypes from 'dashboard/i18n/locale/es/attributesMgmt.json';

const { admin, captainEnabled } = vi.hoisted(() => ({
  admin: { value: true },
  captainEnabled: { value: true },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(7),
    isCloudFeatureEnabled: () => captainEnabled.value,
    accountScopedRoute: (name, params) => ({
      name,
      params: { accountId: 7, ...params },
    }),
  }),
}));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => admin.value) }) };
});
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getConnections: vi.fn(),
    getCalendars: vi.fn(),
    getTemplateDrafts: vi.fn(),
    getActivationKit: vi.fn(),
    getAppointmentAttributes: vi.fn(),
  },
}));
vi.mock('dashboard/api/captain/assistant', () => ({
  default: { get: vi.fn() },
}));
vi.mock('../../components/BaseSettingsHeader.vue', () => ({
  default: { props: ['title'], template: '<header>{{ title }}</header>' },
}));
const calendar = {
  id: 'sales',
  summary: 'Sales',
  enabled: true,
  connection: { id: 1, provider: 'google', email: 'owner@example.com' },
};
const assistant = {
  id: 11,
  name: 'Aurora',
  config: {
    appointments: {
      enabled: true,
      calendar_connection_id: 1,
      calendar_id: 'sales',
    },
  },
};
const render = async (query = {}, locale = 'en') => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: Index },
      {
        path: '/attributes',
        name: 'attributes_list',
        component: { template: '<div />' },
      },
      {
        path: '/integrations',
        name: 'settings_integrations_calendars',
        component: { template: '<div />' },
      },
      {
        path: '/assistant/:assistantId',
        name: 'captain_assistants_settings_appointments_index',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push({ path: '/', query });
  await router.isReady();
  const wrapper = mount(RouterView, {
    global: {
      plugins: [
        router,
        createStore({ modules: { calendarConnections } }),
        createI18n({
          legacy: false,
          locale,
          messages: { en: { ...en, ...enTypes }, es: { ...es, ...esTypes } },
        }),
      ],
      stubs: {
        CalendarHours: true,
        CalendarTemplates: {
          emits: ['updated'],
          template: '<div data-testid="messages" />',
        },
        CalendarInvitationSettings: {
          emits: ['dirty'],
          template:
            '<div><button data-testid="edit-invitation" @click="$emit(\'dirty\', true)">Edit</button><button data-testid="save-invitation" @click="$emit(\'dirty\', false)">Save</button></div>',
        },
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
};
beforeEach(() => {
  vi.clearAllMocks();
  admin.value = true;
  captainEnabled.value = true;
  CalendarAPI.getConnections.mockResolvedValue({
    data: { payload: [calendar.connection] },
  });
  CalendarAPI.getCalendars.mockResolvedValue({ data: { payload: [calendar] } });
  CalendarAPI.getTemplateDrafts.mockResolvedValue({
    data: { results: {}, prepared_language: null },
  });
  CalendarAPI.getActivationKit.mockResolvedValue({
    data: { reminder_enabled: false },
  });
  CalendarAPI.getAppointmentAttributes.mockResolvedValue({
    data: {
      keys: [
        'ultima_cita',
        'proxima_cita',
        'proxima_cita_titulo',
        'total_citas',
      ],
      enabled_keys: [
        'ultima_cita',
        'proxima_cita',
        'proxima_cita_titulo',
        'total_citas',
      ],
      results: {},
    },
  });
  AssistantAPI.get.mockResolvedValue({ data: { payload: [assistant] } });
});
describe('Citas panel', () => {
  it('defaults to Overview, loads all summary data and navigates with a query', async () => {
    const { wrapper, router } = await render();
    expect(wrapper.get('button[aria-current="page"]').text()).toBe('Overview');
    expect(wrapper.text()).toContain(
      '1 with a calendar; 0 without an available calendar'
    );
    expect(wrapper.text()).toContain('not been prepared');
    expect(wrapper.find('[data-testid="messages"]').exists()).toBe(false);
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Calendars')
      .trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.query.tab).toBe('calendarios');
    expect(wrapper.findComponent(CalendarResources).isVisible()).toBe(true);
    expect(wrapper.text()).toContain('Aurora');
  });
  it('protects unsaved invitation edits including URL navigation', async () => {
    const { wrapper, router } = await render({ tab: 'invitacion' });
    await wrapper.get('[data-testid="edit-invitation"]').trigger('click');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Overview')
      .trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.query.tab).toBe('invitacion');
    expect(wrapper.get('[role="alert"]').text()).toContain('unsaved');
    await router.push({ query: { tab: 'mensajes' } });
    expect(router.currentRoute.value.query.tab).toBe('invitacion');
    await wrapper.get('[data-testid="save-invitation"]').trigger('click');
    await router.push({ query: { tab: 'mensajes' } });
    await flushPromises();
    expect(wrapper.get('[data-testid="messages"]').isVisible()).toBe(true);
  });
  it.each(['atributos', 'unknown'])(
    'opens Overview for the obsolete or unknown tab %s',
    async tab => {
      const { wrapper } = await render({ tab });
      expect(wrapper.get('button[aria-current="page"]').text()).toBe(
        'Overview'
      );
      expect(
        wrapper.findAll('nav button').map(button => button.text())
      ).toEqual(['Overview', 'Calendars', 'Messages', 'Invitation']);
      expect(
        wrapper.find('calendar-appointment-attributes-stub').exists()
      ).toBe(false);
    }
  );
  it.each([
    ['en', '4 active'],
    ['es', '4 activos'],
  ])(
    'shows automatic attributes as read only in %s',
    async (locale, expected) => {
      const { wrapper } = await render({}, locale);
      const status = wrapper.get(
        '[data-testid="appointment-attributes-status"]'
      );
      expect(CalendarAPI.getAppointmentAttributes).toHaveBeenCalledOnce();
      expect(status.text()).toContain(expected);
      expect(status.findAll('button, input, a')).toHaveLength(0);
    }
  );
  it.each([
    ['en', 'Created when you connect Google.'],
    ['es', 'Se crean al conectar Google.'],
  ])('explains unprepared attributes in %s', async (locale, expected) => {
    CalendarAPI.getAppointmentAttributes.mockResolvedValue({
      data: { keys: null, enabled_keys: [], results: {} },
    });
    const { wrapper } = await render({}, locale);
    expect(
      wrapper.get('[data-testid="appointment-attributes-status"]').text()
    ).toContain(expected);
  });
  it.each([
    ['en', 'Text', 'Date', 'Custom Attributes'],
    ['es', 'Texto', 'Fecha', 'Atributos personalizados'],
  ])(
    'shows each type conflict and a link to custom attributes in %s',
    async (locale, actual, expected, link) => {
      CalendarAPI.getAppointmentAttributes.mockResolvedValue({
        data: {
          keys: ['ultima_cita', 'proxima_cita'],
          enabled_keys: [],
          results: {
            ultima_cita: {
              status: 'conflict',
              actual_type: 'text',
              expected_type: 'datetime',
            },
            proxima_cita: {
              status: 'conflict',
              actual_type: 'number',
              expected_type: 'datetime',
            },
          },
        },
      });
      const { wrapper } = await render({}, locale);
      const status = wrapper.get(
        '[data-testid="appointment-attributes-status"]'
      );
      expect(status.findAll('[role="alert"]')).toHaveLength(2);
      expect(status.text()).toContain(
        locale === 'es' ? '0 activos' : '0 active'
      );
      expect(status.get('[role="alert"]').text()).toContain('ultima_cita');
      expect(status.get('[role="alert"]').text()).toContain(actual);
      expect(status.get('[role="alert"]').text()).toContain(expected);
      expect(status.text()).toContain('proxima_cita');
      expect(status.get('a').attributes('href')).toBe('/attributes');
      expect(status.get('a').text()).toContain(link);
      expect(status.findAll('button, input')).toHaveLength(0);
    }
  );
  it('shows an attribute load error instead of announcing successful preparation', async () => {
    CalendarAPI.getAppointmentAttributes.mockRejectedValueOnce(
      new Error('offline')
    );
    const { wrapper } = await render();
    const status = wrapper.get('[data-testid="appointment-attributes-status"]');
    expect(status.text()).toContain('could not be loaded');
    expect(status.text()).not.toContain('4 active');
    expect(status.text()).not.toContain('Created when');
  });
  it('shows the disconnected continuity notice for prior configuration', async () => {
    CalendarAPI.getConnections.mockResolvedValue({ data: { payload: [] } });
    const { wrapper } = await render();
    expect(wrapper.text()).toContain('notices are paused');
    expect(wrapper.text()).toContain('Reconnect');
    expect(wrapper.text()).toContain('No enabled calendars');
  });
  it('reports failed sections instead of reporting zero assistants', async () => {
    AssistantAPI.get.mockRejectedValueOnce(new Error('denied'));
    const { wrapper } = await render({ tab: 'calendarios' });
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'could not be loaded'
    );
    expect(wrapper.text()).not.toContain('Human team only');
    expect(wrapper.text()).not.toContain('No assistants.');
  });
  it('does not fetch Captain when the feature is disabled', async () => {
    captainEnabled.value = false;
    const { wrapper } = await render();
    expect(AssistantAPI.get).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('No assistants.');
  });
  it('does not load settings for agents', async () => {
    admin.value = false;
    const { wrapper } = await render();
    expect(CalendarAPI.getConnections).not.toHaveBeenCalled();
    expect(AssistantAPI.get).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('administrator');
  });
  it('updates Overview after message changes without reloading assistants', async () => {
    const { wrapper, router } = await render({ tab: 'mensajes' });
    wrapper.findComponent(CalendarTemplates).vm.$emit('updated', {
      drafts: {
        results: { reminder: { destinations: [{ state: 'usable' }] } },
      },
      kit: { reminder_enabled: true },
    });
    await router.push({ query: { tab: 'resumen' } });
    await flushPromises();
    expect(wrapper.getComponent(CalendarSummary).text()).toContain('Enabled.');
    expect(AssistantAPI.get).toHaveBeenCalledOnce();
  });
  it('keeps English and Spanish panel keys in parity', () => {
    expect(Object.keys(en.CITAS_PANEL)).toEqual(Object.keys(es.CITAS_PANEL));
    expect(Object.keys(en.CITAS_PANEL.LINK_REASONS)).toEqual(
      Object.keys(es.CITAS_PANEL.LINK_REASONS)
    );
  });
  it.each(
    [
      [],
      [assistant],
      [assistant, { ...assistant, id: 12, name: 'Mateo' }],
      [
        {
          ...assistant,
          config: {
            appointments: { calendar_connection_id: 2, calendar_id: 'sales' },
          },
        },
      ],
    ].map(items => [items])
  )('maps calendars by both IDs: %j', async assistants => {
    AssistantAPI.get.mockResolvedValue({ data: { payload: assistants } });
    const { wrapper } = await render({ tab: 'calendarios' });
    const resources = wrapper.getComponent(CalendarResources);
    const assigned = assistants.filter(
      item => item.config.appointments.calendar_connection_id === 1
    );
    expect(
      resources
        .findAll('a')
        .filter(link => link.text() === 'Configure assistant')
    ).toHaveLength(assigned.length);
    expect(resources.text().includes('Human team only')).toBe(!assigned.length);
    expect(
      resources.findAll('a').filter(link => link.text() === 'Choose calendar')
    ).toHaveLength(assistants.length - assigned.length);
    expect(resources.find('select').exists()).toBe(false);
    expect(resources.findComponent({ name: 'ComboBox' }).exists()).toBe(false);
    expect(resources.get('[role="status"]').text()).toBe('Open');
  });
  it('summarizes destination states without treating pending destinations as ready', async () => {
    CalendarAPI.getTemplateDrafts.mockResolvedValue({
      data: {
        results: {
          reminder: {
            destinations: [
              { state: 'usable' },
              { state: 'pending_approval' },
              { state: 'incompatible', reason: 'explicit_link_required' },
              { state: 'missing' },
            ],
          },
        },
      },
    });
    const { wrapper } = await render();
    expect(wrapper.getComponent(CalendarSummary).text()).toContain(
      '1 ready · 1 approved, awaiting link · 1 in review · 1 pending'
    );
  });
  it.each([
    ['en', '2 ready · 2 in review · 1 pending'],
    ['es', '2 listas · 2 en revisión · 1 pendiente'],
  ])(
    'omits zero counts and pluralizes the template summary in %s',
    async (locale, expected) => {
      CalendarAPI.getTemplateDrafts.mockResolvedValue({
        data: {
          results: {
            reminder: {
              destinations: [
                { state: 'usable' },
                { state: 'usable' },
                { state: 'pending_approval' },
                { state: 'pending_approval' },
                { state: 'missing' },
              ],
            },
          },
        },
      });
      const { wrapper } = await render({}, locale);
      expect(wrapper.getComponent(CalendarSummary).text()).toContain(expected);
      expect(wrapper.getComponent(CalendarSummary).text()).not.toMatch(
        /0 (approved|aprobadas)/
      );
    }
  );
});
