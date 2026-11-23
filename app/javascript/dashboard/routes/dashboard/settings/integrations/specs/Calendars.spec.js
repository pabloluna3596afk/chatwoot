import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import Calendars from '../Calendars.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import calendarConnections from 'dashboard/store/modules/calendarConnections';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../components/BaseSettingsHeader.vue', () => ({
  default: {
    props: ['title', 'description'],
    template: '<header>{{ title }}</header>',
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {} }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(7),
    accountScopedRoute: name => ({ name, params: { accountId: 7 } }),
  }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getConnections: vi.fn(),
    getCalendars: vi.fn(),
    disconnect: vi.fn(),
  },
}));

describe('Calendars integration connection settings', () => {
  it.each([true, false])(
    'links to Citas only with a Google connection: %s',
    async connected => {
      CalendarAPI.getConnections.mockResolvedValue({
        data: {
          configured: true,
          payload: connected
            ? [{ id: 1, provider: 'google', email: 'test@example.com' }]
            : [],
        },
      });
      CalendarAPI.getCalendars.mockResolvedValue({ data: { payload: [] } });
      const store = createStore({
        modules: {
          calendarConnections,
          integrations: {
            namespaced: true,
            getters: { getIntegration: () => () => ({}) },
            actions: { get: vi.fn() },
          },
        },
      });
      const wrapper = shallowMount(Calendars, {
        global: {
          plugins: [store],
          mocks: { $t: key => key },
          stubs: {
            SettingsLayout: false,
            RouterLink: {
              props: ['to'],
              template: '<a :data-route="to.name"><slot /></a>',
            },
            Dialog: {
              template: '<div />',
              methods: { open: vi.fn(), close: vi.fn() },
            },
          },
        },
      });
      await flushPromises();
      expect(wrapper.find('[data-testid="configure-citas"]').exists()).toBe(
        connected
      );
      expect(wrapper.find('calendar-templates-stub').exists()).toBe(false);
      expect(
        wrapper.find('calendar-appointment-attributes-stub').exists()
      ).toBe(false);
      expect(wrapper.find('calendar-invitation-settings-stub').exists()).toBe(
        false
      );
      if (connected) {
        expect(
          wrapper
            .get('[data-testid="configure-citas"]')
            .attributes('data-route')
        ).toBe('settings_citas');
        wrapper
          .findAllComponents(Button)
          .find(
            button =>
              button.props('label') ===
              'INTEGRATION_SETTINGS.CALENDARS.DISCONNECT'
          )
          .vm.$emit('click');
        CalendarAPI.disconnect.mockResolvedValue({});
        CalendarAPI.getConnections.mockResolvedValue({
          data: { configured: true, payload: [] },
        });
        wrapper.findComponent(Dialog).vm.$emit('confirm');
        await flushPromises();
        expect(CalendarAPI.disconnect).toHaveBeenCalledWith(1);
        expect(wrapper.find('[data-testid="configure-citas"]').exists()).toBe(
          false
        );
        expect(
          store.getters['calendarConnections/hasGoogleConnection'](7)
        ).toBe(false);
      }
      wrapper.unmount();
    }
  );
});
