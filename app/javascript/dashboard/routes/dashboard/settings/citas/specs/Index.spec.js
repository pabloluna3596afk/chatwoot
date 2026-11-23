import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import Index from '../Index.vue';
import routes from '../citas.routes';
import CalendarTemplates from '../CalendarTemplates.vue';
import CalendarAppointmentAttributes from '../CalendarAppointmentAttributes.vue';
import CalendarInvitationSettings from '../CalendarInvitationSettings.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import SettingsLayout from '../../SettingsLayout.vue';
import calendarConnections from 'dashboard/store/modules/calendarConnections';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';

const { admin } = vi.hoisted(() => ({ admin: { value: true } }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../components/BaseSettingsHeader.vue', () => ({
  default: {
    props: ['title', 'description'],
    template: '<header>{{ title }}</header>',
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(7),
    accountScopedRoute: name => ({ name, params: { accountId: 7 } }),
  }),
}));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => admin.value) }) };
});
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConnections: vi.fn() },
}));

beforeEach(() => {
  admin.value = true;
});

describe('Citas settings page', () => {
  it.each([true, false])(
    'composes cards only with an active Google connection: %s',
    async connected => {
      CalendarAPI.getConnections.mockResolvedValue({
        data: { payload: connected ? [{ id: 1, provider: 'google' }] : [] },
      });
      const store = createStore({ modules: { calendarConnections } });
      const wrapper = shallowMount(Index, {
        global: {
          plugins: [store],
          mocks: { $t: key => key },
          stubs: {
            SettingsLayout: false,
            RouterLink: {
              props: ['to'],
              template: '<a :data-route="to.name"><slot /></a>',
            },
          },
        },
      });
      await flushPromises();
      expect(wrapper.getComponent(BaseSettingsHeader).props('title')).toBe(
        'SIDEBAR.CITAS'
      );
      expect(wrapper.getComponent(SettingsLayout).props('isLoading')).toBe(
        false
      );
      expect(wrapper.findComponent(CalendarTemplates).exists()).toBe(connected);
      expect(
        wrapper.findComponent(CalendarAppointmentAttributes).exists()
      ).toBe(connected);
      expect(wrapper.findComponent(CalendarInvitationSettings).exists()).toBe(
        connected
      );
      if (connected) {
        expect(wrapper.getComponent(CalendarTemplates).props('connected')).toBe(
          true
        );
        expect(wrapper.html().indexOf('calendar-templates-stub')).toBeLessThan(
          wrapper.html().indexOf('calendar-appointment-attributes-stub')
        );
        expect(
          wrapper.html().indexOf('calendar-appointment-attributes-stub')
        ).toBeLessThan(
          wrapper.html().indexOf('calendar-invitation-settings-stub')
        );
      } else {
        expect(wrapper.text()).toContain('CALENDAR_TEMPLATES.CONNECT_GOOGLE');
      }
      expect(wrapper.get('a').attributes('data-route')).toBe(
        'settings_integrations_calendars'
      );
      wrapper.unmount();
    }
  );

  it('does not load or mount editable settings for an agent', async () => {
    admin.value = false;
    const store = createStore({ modules: { calendarConnections } });
    const wrapper = shallowMount(Index, {
      global: {
        plugins: [store],
        mocks: { $t: key => key },
        stubs: { SettingsLayout: false },
      },
    });
    await flushPromises();
    expect(CalendarAPI.getConnections).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('CALENDAR_TEMPLATES.ADMIN_ONLY');
    expect(wrapper.findComponent(CalendarTemplates).exists()).toBe(false);
    wrapper.unmount();
  });

  it('offers recovery after a connection load failure', async () => {
    CalendarAPI.getConnections.mockRejectedValueOnce(new Error('offline'));
    const store = createStore({ modules: { calendarConnections } });
    const wrapper = shallowMount(Index, {
      global: {
        plugins: [store],
        mocks: { $t: key => key },
        stubs: { SettingsLayout: false },
      },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('LOAD_ERROR');
    CalendarAPI.getConnections.mockResolvedValue({
      data: { payload: [{ id: 1, provider: 'google' }] },
    });
    wrapper.getComponent(Button).vm.$emit('click');
    await flushPromises();
    expect(wrapper.findComponent(CalendarTemplates).exists()).toBe(true);
    wrapper.unmount();
  });

  it('registers its own admin route and matching translations', () => {
    expect(routes.routes[0].path).toContain(
      'accounts/:accountId/settings/citas'
    );
    expect(routes.routes[0].children[0]).toMatchObject({
      name: 'settings_citas',
      meta: {
        permissions: ['administrator'],
        featureFlag: FEATURE_FLAGS.CALENDAR,
      },
    });
    expect(Object.keys(en.CITAS_SETTINGS)).toEqual(
      Object.keys(es.CITAS_SETTINGS)
    );
  });
});
