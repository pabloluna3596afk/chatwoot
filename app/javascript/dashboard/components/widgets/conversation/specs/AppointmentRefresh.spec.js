import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import NextAppointmentCard from '../NextAppointmentCard.vue';
import CalendarEventsList from '../CalendarEventsList.vue';

const { contactEvents, conversationEvents } = vi.hoisted(() => ({
  contactEvents: vi.fn(),
  conversationEvents: vi.fn(),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getContactEvents: contactEvents,
    getConversationEvents: conversationEvents,
    getConnections: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({}),
  }),
}));
vi.mock('dashboard/helper/useCalendarCancelledVisibility', () => ({
  useCalendarCancelledVisibility: () => ({ showCancelled: ref(true) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('en') }),
}));
const response = payload => ({ data: { payload } });
const event = (summary, end = '2026-10-21T12:01:00Z') => ({
  id: summary,
  summary,
  start: '2026-10-21T12:00:00Z',
  end,
});
const wrappers = [];
const mount = (component, id = 7) => {
  const wrapper = shallowMount(component, {
    props: {
      contactId: id,
      ...(component === CalendarEventsList ? { conversationId: id } : {}),
    },
    global: { mocks: { $t: key => key } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-21T11:59:00Z'));
  contactEvents.mockResolvedValue(response([]));
  conversationEvents.mockResolvedValue(response([]));
});
afterEach(() => {
  wrappers.splice(0).forEach(w => w.unmount());
  vi.useRealTimers();
});

it.each([NextAppointmentCard, CalendarEventsList])(
  'refreshes only the matching contact and account without remounting %s',
  async component => {
    const api =
      component === NextAppointmentCard ? contactEvents : conversationEvents;
    const a = mount(component, 7);
    const b = mount(component, 8);
    await flushPromises();
    api.mockResolvedValue(response([event('Updated')]));
    emitter.emit('calendar.events_changed', {
      account_id: 2,
      contact_ids: [7],
    });
    await flushPromises();
    expect(api).toHaveBeenCalledTimes(2);
    emitter.emit('calendar.events_changed', {
      account_id: 1,
      contact_ids: [7],
    });
    await flushPromises();
    expect(a.text()).toContain('Updated');
    expect(b.text()).not.toContain('Updated');
    expect(api).toHaveBeenCalledTimes(3);
  }
);

it.each([NextAppointmentCard, CalendarEventsList])(
  'distinguishes a failed request from empty and retries %s',
  async component => {
    const api =
      component === NextAppointmentCard ? contactEvents : conversationEvents;
    api.mockRejectedValueOnce(new Error('HTTP 503'));
    const wrapper = mount(component);
    await flushPromises();
    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR'
    );
    expect(wrapper.text()).not.toContain('CONVERSATION_SIDEBAR.CALENDAR.EMPTY');
    wrapper.findAllComponents({ name: 'Button' }).at(-1).vm.$emit('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR'
    );
    expect(wrapper.text()).toContain(
      component === NextAppointmentCard
        ? 'CONVERSATION_SIDEBAR.CALENDAR.NEXT_EMPTY'
        : 'CONVERSATION_SIDEBAR.CALENDAR.EMPTY'
    );
  }
);

it('advances to the next appointment after the current one ends without fetching', async () => {
  contactEvents.mockResolvedValue(
    response([
      event('First'),
      event('Second', '2026-10-21T13:00:00Z'),
      { ...event('Cancelled'), appointment_status: 'cancelled' },
    ])
  );
  const wrapper = mount(NextAppointmentCard);
  await flushPromises();
  expect(wrapper.text()).toContain('First');
  await vi.advanceTimersByTimeAsync(120001);
  expect(wrapper.text()).toContain('Second');
  expect(wrapper.text()).not.toContain('First');
  expect(contactEvents).toHaveBeenCalledTimes(1);
});

it('ignores a late response from a previous contact', async () => {
  let resolveOld;
  contactEvents.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  const wrapper = mount(NextAppointmentCard);
  contactEvents.mockResolvedValue(response([event('Contact B')]));
  await wrapper.setProps({ contactId: 8 });
  await flushPromises();
  resolveOld(response([event('Contact A')]));
  await flushPromises();
  expect(wrapper.text()).toContain('Contact B');
  expect(wrapper.text()).not.toContain('Contact A');
});

it('reclassifies the list when the appointment ends, and keeps an ongoing appointment upcoming', async () => {
  conversationEvents.mockResolvedValue(response([event('Ongoing')]));
  const wrapper = mount(CalendarEventsList);
  await flushPromises();
  await vi.advanceTimersByTimeAsync(60001);
  expect(wrapper.find('section').text()).toContain(
    'CONVERSATION_SIDEBAR.CALENDAR.UPCOMING'
  );
  await vi.advanceTimersByTimeAsync(60000);
  expect(wrapper.find('section').text()).toContain(
    'CONVERSATION_SIDEBAR.CALENDAR.PAST'
  );
  expect(conversationEvents).toHaveBeenCalledTimes(1);
});

it('resumes the local clock when a suspended tab becomes visible and removes subscriptions on unmount', async () => {
  contactEvents.mockResolvedValue(response([event('Expired')]));
  const wrapper = mount(NextAppointmentCard);
  await flushPromises();
  vi.setSystemTime(new Date('2026-10-21T14:00:00Z'));
  document.dispatchEvent(new Event('visibilitychange'));
  await flushPromises();
  expect(wrapper.text()).not.toContain('Expired');
  wrapper.unmount();
  emitter.emit('calendar.events_changed', { account_id: 1, contact_ids: [7] });
  emitter.emit('WEBSOCKET_RECONNECT_COMPLETED');
  await flushPromises();
  expect(contactEvents).toHaveBeenCalledTimes(1);
});

it('reloads after websocket recovery so missed invalidations do not persist', async () => {
  const wrapper = mount(NextAppointmentCard);
  await flushPromises();
  contactEvents.mockResolvedValue(response([event('Recovered')]));
  emitter.emit('WEBSOCKET_RECONNECT_COMPLETED');
  await flushPromises();
  expect(wrapper.text()).toContain('Recovered');
});
