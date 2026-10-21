import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import CalendarView from '../CalendarView.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import WeekGrid from '../WeekGrid.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: path => path,
    currentAccount: ref({}),
  }),
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
    expect(CalendarAPI.getCalendars).toHaveBeenLastCalledWith('8', {
      signal: expect.any(AbortSignal),
    });
    expect(trigger.text()).toContain('Ventas');
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});

it('shows the cancelled switch beside the legend without changing header contents and filters events', async () => {
  CalendarAPI.getConnections.mockResolvedValue({
    data: { payload: [{ id: 7, name: 'Consultas', provider: 'google' }] },
  });
  CalendarAPI.getCalendars.mockResolvedValue({
    data: { payload: [{ id: 'cal-1', summary: 'Appointments' }] },
  });
  const events = [
    {
      id: 'live',
      summary: 'Consultation',
      start: '2030-01-15T10:00:00-05:00',
      end: '2030-01-15T10:30:00-05:00',
    },
    {
      id: 'cancelled',
      summary: 'Cancelled consultation',
      start: '2030-01-15T11:00:00-05:00',
      end: '2030-01-15T11:30:00-05:00',
      appointment_status: 'cancelled',
    },
  ];
  CalendarAPI.getEvents.mockResolvedValue({ data: { payload: events } });
  const wrapper = shallowMount(CalendarView, {
    global: { mocks: { $t: key => key } },
  });
  try {
    await flushPromises();
    const header = wrapper.get('header');
    const headerText = header.text();
    const toggle = header
      .findAllComponents(Button)
      .find(button => button.props('icon') === 'i-lucide-ellipsis-vertical');
    expect(wrapper.findComponent(Switch).exists()).toBe(false);
    expect(wrapper.getComponent(WeekGrid).props('events')).toEqual([events[0]]);

    await toggle.trigger('click');
    const control = wrapper.get('#calendar-cancelled-visibility');
    expect(header.element.contains(control.element)).toBe(false);
    expect(control.element.parentElement.textContent).toContain(
      'SIDEBAR.CALENDAR_PAGE.STATUS.CONFIRMED'
    );
    expect(header.text()).toBe(headerText);
    expect(toggle.attributes('aria-expanded')).toBe('true');

    wrapper.getComponent(Switch).vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(wrapper.getComponent(WeekGrid).props('events')).toEqual(events);
    expect(header.text()).toBe(headerText);
    await toggle.trigger('click');
    expect(wrapper.findComponent(Switch).exists()).toBe(false);
    expect(wrapper.getComponent(WeekGrid).props('events')).toEqual(events);
  } finally {
    wrapper.unmount();
  }
});
