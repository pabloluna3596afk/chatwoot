import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import CalendarView from '../CalendarView.vue';
import EventModal from '../EventModal.vue';
import CalendarEventsList from 'dashboard/components/widgets/conversation/CalendarEventsList.vue';
import AssistantAppointmentsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantAppointmentsForm.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import ContactAPI from 'dashboard/api/contacts';
import SearchAPI from 'dashboard/api/search';
import VariablesAPI from 'dashboard/api/variables';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({}),
    accountScopedRoute: x => x,
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref([]),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/helper/useCalendarCancelledVisibility', () => ({
  useCalendarCancelledVisibility: () => ({ showCancelled: ref(false) }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getConnections: vi.fn(),
    getCalendars: vi.fn(),
    getEvents: vi.fn(),
    getConversationEvents: vi.fn(),
    getInvitation: vi.fn(),
    lockEvent: vi.fn(),
    unlockEvent: vi.fn(),
    createEvent: vi.fn(),
    updateEvent: vi.fn(),
  },
}));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/api/search', () => ({
  default: { conversations: vi.fn() },
}));
vi.mock('dashboard/api/variables', () => ({
  default: { catalog: vi.fn().mockResolvedValue({ data: { variables: [] } }) },
}));

const response = payload => ({ data: { payload } });
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
};
const wrappers = [];
const render = (component, props = {}) => {
  const wrapper = shallowMount(component, {
    props,
    global: {
      mocks: { $t: x => x },
      stubs: {
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
        EventModal: {
          template: '<div />',
          methods: { close() {} },
        },
        RouterLink: true,
      },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};

beforeEach(() => {
  VariablesAPI.catalog.mockResolvedValue({ data: { variables: [] } });
  CalendarAPI.getConnections.mockResolvedValue(
    response([
      { id: 1, provider: 'google', email: 'first@example.com' },
      { id: 2, provider: 'google', email: 'second@example.com' },
    ])
  );
  CalendarAPI.getCalendars.mockResolvedValue(response([{ id: 'shared' }]));
  CalendarAPI.getEvents.mockResolvedValue(response([]));
  CalendarAPI.getConversationEvents.mockResolvedValue(response([]));
  CalendarAPI.getInvitation.mockResolvedValue({ data: {} });
  CalendarAPI.lockEvent.mockResolvedValue({});
  CalendarAPI.unlockEvent.mockResolvedValue({});
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('reloads the same calendar ID on connection change and discards old weeks and unmounted responses', async () => {
  const wrapper = render(CalendarView);
  await flushPromises();
  const state = wrapper.vm.$.setupState;
  const old = deferred();
  CalendarAPI.getEvents.mockReturnValueOnce(old.promise);
  state.weekStartKey = '2030-01-07';
  await flushPromises();
  const oldSignal = CalendarAPI.getEvents.mock.lastCall[0].signal;
  state.selectedConnectionId = '2';
  await flushPromises();
  expect(CalendarAPI.getEvents.mock.lastCall[0].connectionId).toBe('2');
  expect(oldSignal.aborted).toBe(true);
  old.resolve(response([{ id: 'obsolete' }]));
  await flushPromises();
  expect(state.events).toEqual([]);
  const pending = deferred();
  CalendarAPI.getEvents.mockReturnValueOnce(pending.promise);
  state.weekStartKey = '2030-01-14';
  await flushPromises();
  const signal = CalendarAPI.getEvents.mock.lastCall[0].signal;
  wrapper.unmount();
  expect(signal.aborted).toBe(true);
  pending.resolve(response([{ id: 'unmounted' }]));
  await flushPromises();
  expect(state.events).toEqual([]);
});

it('keeps the newest calendar options and suppresses an obsolete error', async () => {
  const wrapper = render(CalendarView);
  await flushPromises();
  const state = wrapper.vm.$.setupState;
  const old = deferred();
  CalendarAPI.getCalendars.mockReturnValueOnce(old.promise);
  state.selectedConnectionId = '2';
  await flushPromises();
  const signal = CalendarAPI.getCalendars.mock.lastCall[1]?.signal;
  state.selectedConnectionId = '1';
  await flushPromises();
  old.reject(new Error('old connection'));
  await flushPromises();
  expect(signal?.aborted).toBe(true);
  expect(state.calendars).toEqual([{ id: 'shared' }]);
  expect(useAlert).not.toHaveBeenCalled();
});

it('discards old conversations on prop change and aborts on disposal', async () => {
  const old = deferred();
  CalendarAPI.getConversationEvents.mockReturnValueOnce(old.promise);
  const wrapper = render(CalendarEventsList, { conversationId: 1 });
  await flushPromises();
  const oldSignal = CalendarAPI.getConversationEvents.mock.lastCall[1]?.signal;
  await wrapper.setProps({ conversationId: 2 });
  await flushPromises();
  old.resolve(response([{ id: 'old conversation' }]));
  await flushPromises();
  expect(wrapper.vm.$.setupState.events).toEqual([]);
  expect(oldSignal?.aborted).toBe(true);
  const pending = deferred();
  CalendarAPI.getConversationEvents.mockReturnValueOnce(pending.promise);
  await wrapper.setProps({ conversationId: 3 });
  const signal = CalendarAPI.getConversationEvents.mock.lastCall[1]?.signal;
  wrapper.unmount();
  expect(signal?.aborted).toBe(true);
  pending.resolve(response([]));
  await flushPromises();
});

it('loads the owner options on edit and allows a second connection on create', async () => {
  const wrapper = render(EventModal, {
    connections: [{ id: 1 }, { id: 2 }],
    calendars: [{ id: 'wrong-owner' }],
  });
  await wrapper.vm.open({ defaults: { connectionId: '1' } });
  await flushPromises();
  const state = wrapper.vm.$.setupState;
  const connection = wrapper
    .findAllComponents({ name: 'OutlinedSelectField' })
    .find(
      field => field.attributes('data-testid') === 'appointment-connection'
    );
  expect(connection.props('disabled')).toBe(false);
  state.connectionId = '2';
  await flushPromises();
  expect(CalendarAPI.getCalendars.mock.lastCall[0]).toBe('2');
  expect(state.calendarId).toBe('shared');
  await wrapper.vm.open({
    event: { id: 'owned', connection_id: 2, calendar_id: 'shared' },
  });
  await flushPromises();
  expect(connection.props('disabled')).toBe(true);
  expect(state.calendarOptions.map(option => option.value)).toEqual(['shared']);
});

it('creates on the second connection and keeps that owner when editing', async () => {
  const wrapper = render(EventModal, { connections: [{ id: 1 }, { id: 2 }] });
  await wrapper.vm.open({
    defaults: { connectionId: '1', dateKey: '2030-01-15' },
  });
  await flushPromises();
  const state = wrapper.vm.$.setupState;
  state.connectionId = '2';
  state.summary = 'Second account';
  await flushPromises();
  CalendarAPI.createEvent.mockResolvedValue(response({ id: 'created' }));
  await state.save();
  expect(CalendarAPI.createEvent).toHaveBeenCalledWith(
    expect.objectContaining({
      connection_id: '2',
      calendar_id: 'shared',
    })
  );
  await wrapper.vm.open({
    event: {
      id: 'created',
      connection_id: 2,
      calendar_id: 'shared',
      summary: 'Edited',
      start: '2030-01-15T10:00:00-05:00',
      end: '2030-01-15T10:30:00-05:00',
    },
  });
  await flushPromises();
  CalendarAPI.updateEvent.mockResolvedValue(response({ id: 'created' }));
  await state.save();
  expect(CalendarAPI.updateEvent).toHaveBeenCalledWith(
    'created',
    expect.objectContaining({
      connection_id: '2',
      calendar_id: 'shared',
    })
  );
});

it('discards reverse modal calendar results, distinguishes errors and retries', async () => {
  const wrapper = render(EventModal);
  const old = deferred();
  CalendarAPI.getCalendars.mockReturnValueOnce(old.promise);
  await wrapper.vm.open({ defaults: { connectionId: '1' } });
  const signal = CalendarAPI.getCalendars.mock.lastCall[1].signal;
  expect(wrapper.find('[role="status"]').exists()).toBe(true);
  wrapper.vm.$.setupState.connectionId = '2';
  await flushPromises();
  old.resolve(response([{ id: 'obsolete' }]));
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.vm.$.setupState.calendars).toEqual([{ id: 'shared' }]);
  CalendarAPI.getCalendars.mockRejectedValueOnce(
    new Error('provider unavailable')
  );
  await wrapper.vm.$.setupState.loadCalendars();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.vm.$.setupState.confirmDisabled).toBe(true);
  await wrapper.vm.$.setupState.loadCalendars();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  const pending = deferred();
  CalendarAPI.getCalendars.mockReturnValueOnce(pending.promise);
  const loading = wrapper.vm.$.setupState.loadCalendars();
  const lastSignal = CalendarAPI.getCalendars.mock.lastCall[1].signal;
  wrapper.unmount();
  pending.resolve(response([{ id: 'disposed' }]));
  await loading;
  expect(lastSignal.aborted).toBe(true);
  expect(wrapper.vm.$.setupState.calendars).toEqual([]);
});

it('aborts modal invitation, lock and search on close without surfacing cancellation', async () => {
  const invitation = deferred();
  const lock = deferred();
  const search = deferred();
  CalendarAPI.getInvitation.mockReturnValueOnce(invitation.promise);
  CalendarAPI.lockEvent.mockReturnValueOnce(lock.promise);
  ContactAPI.search.mockReturnValueOnce(search.promise);
  const wrapper = render(EventModal);
  const opening = wrapper.vm.open({ event: { id: 'old', connection_id: 1 } });
  const searching = wrapper.vm.$.setupState.onSearchContacts('Alice');
  const invitationSignal = CalendarAPI.getInvitation.mock.lastCall[0].signal;
  const lockSignal = CalendarAPI.lockEvent.mock.lastCall[2].signal;
  const contactSignal = ContactAPI.search.mock.lastCall[4].signal;
  await wrapper.vm.close();
  expect(
    [invitationSignal, lockSignal, contactSignal].every(
      signal => signal.aborted
    )
  ).toBe(true);
  invitation.reject({ code: 'ERR_CANCELED' });
  lock.reject({ name: 'CanceledError' });
  search.reject({ name: 'AbortError' });
  await Promise.all([opening, searching]);
  expect(useAlert).not.toHaveBeenCalled();
});

it('invalidates contact and conversation searches on selection, reopening, short input and disposal', async () => {
  const wrapper = render(EventModal);
  await wrapper.vm.open();
  const state = wrapper.vm.$.setupState;
  const old = deferred();
  ContactAPI.search.mockReturnValueOnce(old.promise);
  const searching = state.onSearchContacts('Alice');
  state.selectContact({ id: 2, name: 'Bob' });
  old.resolve(response([{ id: 1, name: 'Alice' }]));
  await searching;
  expect(state.contactResults).toEqual([]);
  expect(ContactAPI.search.mock.lastCall[4].signal.aborted).toBe(true);
  const conversation = deferred();
  SearchAPI.conversations.mockReturnValueOnce(conversation.promise);
  const finding = state.onSearchConversations('12');
  await state.onSearchConversations('');
  conversation.resolve({ data: { payload: { conversations: [{ id: 12 }] } } });
  await finding;
  expect(state.conversationResults).toEqual([]);
  const pending = deferred();
  ContactAPI.search.mockReturnValueOnce(pending.promise);
  const request = state.onSearchContacts('Charlie');
  await wrapper.vm.open();
  expect(ContactAPI.search.mock.lastCall[4].signal.aborted).toBe(true);
  wrapper.unmount();
  pending.resolve(response([{ id: 3 }]));
  await request;
  expect(state.contactResults).toEqual([]);
});

it('keeps Captain calendar options tied to the latest assistant prop and cancels on disposal', async () => {
  const old = deferred();
  CalendarAPI.getCalendars.mockReturnValueOnce(old.promise);
  const wrapper = render(AssistantAppointmentsForm, {
    assistant: { config: { appointments: { calendar_connection_id: 1 } } },
  });
  await flushPromises();
  const signal = CalendarAPI.getCalendars.mock.calls[0][1]?.signal;
  await wrapper.setProps({
    assistant: { config: { appointments: { calendar_connection_id: 2 } } },
  });
  await flushPromises();
  old.resolve(response([{ id: 'wrong-assistant' }]));
  await flushPromises();
  expect(wrapper.vm.$.setupState.calendars).toEqual([{ id: 'shared' }]);
  expect(signal?.aborted).toBe(true);
  const pending = deferred();
  CalendarAPI.getCalendars.mockReturnValueOnce(pending.promise);
  await wrapper.setProps({ assistant: { config: {} } });
  await wrapper.setProps({
    assistant: { config: { appointments: { calendar_connection_id: 1 } } },
  });
  const lastSignal = CalendarAPI.getCalendars.mock.lastCall[1]?.signal;
  wrapper.unmount();
  expect(lastSignal?.aborted).toBe(true);
  pending.resolve(response([]));
  await flushPromises();
});
