import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import Index from '../Index.vue';
import CalendarResources from '../CalendarResources.vue';
import calendarConnections from 'dashboard/store/modules/calendarConnections';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import AssistantAPI from 'dashboard/api/captain/assistant';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';
import enTypes from 'dashboard/i18n/locale/en/attributesMgmt.json';
import esTypes from 'dashboard/i18n/locale/es/attributesMgmt.json';
import enInvitation from 'dashboard/i18n/locale/en/calendarInvitation.json';
import esInvitation from 'dashboard/i18n/locale/es/calendarInvitation.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import esSettings from 'dashboard/i18n/locale/es/settings.json';
import enIntegrations from 'dashboard/i18n/locale/en/integrations.json';
import esIntegrations from 'dashboard/i18n/locale/es/integrations.json';

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
    getInvitation: vi.fn(),
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
const render = async (query = {}, locale = 'en', realPanels = false) => {
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
          messages: {
            en: {
              ...en,
              ...enTypes,
              ...enInvitation,
              ...enSettings,
              ...enIntegrations,
            },
            es: {
              ...es,
              ...esTypes,
              ...esInvitation,
              ...esSettings,
              ...esIntegrations,
            },
          },
        }),
      ],
      stubs: {
        CalendarHours: true,
        CalendarTemplates: realPanels
          ? false
          : {
              emits: ['updated'],
              template: '<div data-testid="messages" />',
            },
        CalendarInvitationSettings: realPanels
          ? false
          : {
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
  CalendarAPI.getInvitation.mockResolvedValue({
    data: { default_template: 'Hello', max_length: 4000 },
  });
  AssistantAPI.get.mockResolvedValue({ data: { payload: [assistant] } });
});
describe('Citas panel', () => {
  it('defaults to Overview and loads resources only when opening Calendars', async () => {
    const { wrapper, router } = await render();
    expect(wrapper.get('button[aria-current="page"]').text()).toBe('Overview');
    expect(CalendarAPI.getConnections).toHaveBeenCalledOnce();
    expect(CalendarAPI.getCalendars).not.toHaveBeenCalled();
    expect(CalendarAPI.getTemplateDrafts).not.toHaveBeenCalled();
    expect(CalendarAPI.getActivationKit).not.toHaveBeenCalled();
    expect(AssistantAPI.get).not.toHaveBeenCalled();
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
    expect(CalendarAPI.getCalendars).not.toHaveBeenCalled();
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
    const { wrapper } = await render({ tab: 'calendarios' });
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
  it('loads each real panel once across repeated tab visits', async () => {
    const { wrapper, router } = await render({}, 'en', true);
    expect(CalendarAPI.getInvitation).not.toHaveBeenCalled();
    expect(CalendarAPI.getTemplateDrafts).not.toHaveBeenCalled();
    const tabs = [
      'calendarios',
      'mensajes',
      'invitacion',
      'resumen',
      'calendarios',
      'mensajes',
      'invitacion',
      'resumen',
    ];
    await tabs.reduce(async (previous, tab) => {
      await previous;
      await router.push({ query: { tab } });
      await flushPromises();
    }, Promise.resolve());
    expect(CalendarAPI.getConnections).toHaveBeenCalledOnce();
    expect(CalendarAPI.getCalendars).toHaveBeenCalledOnce();
    expect(AssistantAPI.get).toHaveBeenCalledOnce();
    expect(CalendarAPI.getTemplateDrafts).toHaveBeenCalledOnce();
    expect(CalendarAPI.getActivationKit).toHaveBeenCalledOnce();
    expect(CalendarAPI.getInvitation).toHaveBeenCalledOnce();
    expect(CalendarAPI.getAppointmentAttributes).toHaveBeenCalledOnce();
    wrapper.unmount();
  });
  it('shows a healthy calendar while another connection is still pending', async () => {
    let finish;
    const pending = new Promise(resolve => {
      finish = resolve;
    });
    CalendarAPI.getConnections.mockResolvedValue({
      data: {
        payload: [
          calendar.connection,
          { id: 2, provider: 'google', name: 'Waiting' },
        ],
      },
    });
    CalendarAPI.getCalendars.mockImplementation(id =>
      id === 2 ? pending : Promise.resolve({ data: { payload: [calendar] } })
    );
    const { wrapper } = await render({ tab: 'calendarios' });
    expect(wrapper.getComponent(CalendarResources).isVisible()).toBe(true);
    expect(wrapper.getComponent(CalendarResources).text()).toContain('Sales');
    finish({ data: { payload: [] } });
    await flushPromises();
  });
  it('isolates a failed connection and retries only that connection', async () => {
    const second = { id: 2, provider: 'google', name: 'Second connection' };
    CalendarAPI.getConnections.mockResolvedValue({
      data: { payload: [calendar.connection, second] },
    });
    CalendarAPI.getCalendars.mockImplementation(id =>
      id === 2
        ? Promise.reject(new Error('offline'))
        : Promise.resolve({ data: { payload: [calendar] } })
    );
    const { wrapper } = await render({ tab: 'calendarios' });
    const resources = wrapper.getComponent(CalendarResources);
    expect(resources.text()).toContain('Sales');
    expect(resources.get('[role="alert"]').text()).toContain(
      'Second connection'
    );
    CalendarAPI.getCalendars.mockResolvedValue({
      data: { payload: [{ id: 'other', summary: 'Other' }] },
    });
    await resources.get('[role="alert"] button').trigger('click');
    await flushPromises();
    expect(CalendarAPI.getCalendars.mock.calls.map(([id]) => id)).toEqual([
      1, 2, 2,
    ]);
    expect(resources.find('[role="alert"]').exists()).toBe(false);
    expect(resources.text()).toContain('Other');
    expect(AssistantAPI.get).toHaveBeenCalledOnce();
    expect(CalendarAPI.getConnections).toHaveBeenCalledOnce();
  });
  it('retries assistants without reloading calendars', async () => {
    AssistantAPI.get.mockRejectedValueOnce(new Error('offline'));
    const { wrapper } = await render({ tab: 'calendarios' });
    await wrapper
      .getComponent(CalendarResources)
      .get('[role="alert"] button')
      .trigger('click');
    await flushPromises();
    expect(AssistantAPI.get).toHaveBeenCalledTimes(2);
    expect(CalendarAPI.getCalendars).toHaveBeenCalledOnce();
    expect(
      wrapper.getComponent(CalendarResources).find('[role="alert"]').exists()
    ).toBe(false);
  });
  it('retries attributes without reloading connections or other panels', async () => {
    CalendarAPI.getAppointmentAttributes.mockRejectedValueOnce(
      new Error('offline')
    );
    const { wrapper, router } = await render();
    await router.push({ query: { tab: 'mensajes' } });
    await router.push({ query: { tab: 'resumen' } });
    await flushPromises();
    expect(CalendarAPI.getAppointmentAttributes).toHaveBeenCalledOnce();
    await wrapper
      .get('[data-testid="appointment-attributes-status"] button')
      .trigger('click');
    await flushPromises();
    expect(CalendarAPI.getAppointmentAttributes).toHaveBeenCalledTimes(2);
    expect(CalendarAPI.getConnections).toHaveBeenCalledOnce();
    expect(CalendarAPI.getCalendars).not.toHaveBeenCalled();
  });
  it('retries the connection list before requesting resources', async () => {
    CalendarAPI.getConnections.mockRejectedValueOnce(new Error('offline'));
    const { wrapper } = await render({ tab: 'calendarios' });
    expect(CalendarAPI.getCalendars).not.toHaveBeenCalled();
    await wrapper
      .findAll('[role="alert"]')
      .find(alert => alert.isVisible())
      .get('button')
      .trigger('click');
    await flushPromises();
    expect(CalendarAPI.getConnections).toHaveBeenCalledTimes(2);
    expect(CalendarAPI.getCalendars).toHaveBeenCalledOnce();
    expect(wrapper.getComponent(CalendarResources).text()).toContain('Sales');
  });
  it('does not request calendars for non-Google or absent connections', async () => {
    CalendarAPI.getConnections.mockResolvedValue({
      data: { payload: [{ id: 9, provider: 'outlook' }] },
    });
    const { wrapper } = await render({ tab: 'calendarios' });
    expect(CalendarAPI.getCalendars).not.toHaveBeenCalled();
    expect(wrapper.getComponent(CalendarResources).text()).toContain(
      'No enabled calendars'
    );
  });
  it.each(['mensajes', 'invitacion'])(
    'keeps %s errors local and retries only that panel',
    async tab => {
      const api =
        tab === 'mensajes'
          ? CalendarAPI.getTemplateDrafts
          : CalendarAPI.getInvitation;
      api.mockRejectedValueOnce(new Error('offline'));
      const { wrapper, router } = await render({ tab }, 'en', true);
      expect(CalendarAPI.getAppointmentAttributes).not.toHaveBeenCalled();
      const panel = wrapper.get(
        `[data-testid="${tab === 'mensajes' ? 'calendar-templates' : 'invitation-settings'}"]`
      );
      expect(panel.get('[role="alert"]').exists()).toBe(true);
      await router.push({ query: { tab: 'calendarios' } });
      await router.push({ query: { tab } });
      await flushPromises();
      expect(api).toHaveBeenCalledOnce();
      await panel.get('[role="alert"] button').trigger('click');
      await flushPromises();
      expect(api).toHaveBeenCalledTimes(2);
      expect(CalendarAPI.getConnections).toHaveBeenCalledOnce();
      expect(panel.find('[role="alert"]').exists()).toBe(false);
    }
  );
});
