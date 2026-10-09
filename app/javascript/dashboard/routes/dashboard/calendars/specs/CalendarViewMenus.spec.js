import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import CalendarView from '../CalendarView.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: path => path }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/helper/useCalendarCancelledVisibility', () => ({
  useCalendarCancelledVisibility: () => ({ showCancelled: ref(false) }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getConnections: vi.fn().mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Consultas', provider: 'google' },
          { id: 8, name: 'Ventas', provider: 'microsoft' },
        ],
      },
    }),
    getCalendars: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    getEvents: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));

it('uses the real floating menu for calendar accounts and keeps provider logos and selection', async () => {
  CalendarAPI.getConnections.mockResolvedValue({
    data: {
      payload: [
        { id: 7, name: 'Consultas', provider: 'google' },
        { id: 8, name: 'Ventas', provider: 'microsoft' },
      ],
    },
  });
  CalendarAPI.getCalendars.mockResolvedValue({ data: { payload: [] } });
  CalendarAPI.getEvents.mockResolvedValue({ data: { payload: [] } });
  const wrapper = shallowMount(CalendarView, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      stubs: {
        teleport: false,
        MenuPopover: false,
        DropdownMenu: false,
        OutlinedAttributeField: false,
      },
    },
  });
  try {
    await flushPromises();
    const trigger = wrapper.get(
      'button[aria-label="SIDEBAR.CALENDAR_PAGE.ACCOUNT"]'
    );
    await trigger.trigger('click');
    const menu = wrapper.getComponent(DropdownMenu);
    expect(menu.element.parentElement).toBe(document.body);
    expect(menu.classes()).toContain('fixed');
    expect(menu.findAll('img')).toHaveLength(2);
    expect(menu.findAll('.i-lucide-check')).toHaveLength(1);
    await menu.findAll('button')[1].trigger('click');
    await flushPromises();
    expect(CalendarAPI.getCalendars).toHaveBeenLastCalledWith('8');
    expect(trigger.text()).toContain('Ventas');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});
