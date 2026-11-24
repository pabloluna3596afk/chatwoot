import { createStore } from 'vuex';
import { buildCitasMenu } from '../citasMenu';
import calendarConnections from 'dashboard/store/modules/calendarConnections';
import CalendarAPI from 'dashboard/api/integrations/calendar';

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getConnections: vi.fn() },
}));

describe('Citas settings menu', () => {
  it.each([
    [true, true, true, 1],
    [true, true, false, 0],
    [false, true, true, 0],
    [true, false, true, 0],
  ])(
    'checks administrator=%s, feature=%s and Google connection=%s',
    (isAdmin, hasCalendars, hasGoogleConnection, count) => {
      const items = buildCitasMenu({
        isAdmin,
        hasCalendars,
        hasGoogleConnection,
        t: key => key,
        accountScopedRoute: name => ({ name, params: { accountId: 7 } }),
      });
      expect(items).toHaveLength(count);
      if (count)
        expect(items[0]).toEqual({
          name: 'Settings Citas',
          label: 'SIDEBAR.CITAS',
          icon: 'i-lucide-calendar-days',
          to: { name: 'settings_citas', params: { accountId: 7 } },
        });
    }
  );

  it('updates visibility after disconnect without leaking connections between accounts', async () => {
    const store = createStore({ modules: { calendarConnections } });
    CalendarAPI.getConnections.mockResolvedValue({
      data: { payload: [{ id: 1, provider: 'google' }] },
    });
    await store.dispatch('calendarConnections/get', 7);
    expect(store.getters['calendarConnections/hasGoogleConnection'](7)).toBe(
      true
    );
    expect(store.getters['calendarConnections/hasGoogleConnection'](8)).toBe(
      false
    );
    CalendarAPI.getConnections.mockResolvedValue({
      data: { payload: [{ id: 2, provider: 'microsoft' }] },
    });
    await store.dispatch('calendarConnections/get', 8);
    expect(store.getters['calendarConnections/hasGoogleConnection'](8)).toBe(
      false
    );
    CalendarAPI.getConnections.mockResolvedValue({ data: { payload: [] } });
    await store.dispatch('calendarConnections/get', 7);
    expect(store.getters['calendarConnections/hasGoogleConnection'](7)).toBe(
      false
    );
  });
});
