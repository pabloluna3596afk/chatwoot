import { vi } from 'vitest';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import NextAppointmentCard from '../NextAppointmentCard.vue';
import CalendarEventsList from '../CalendarEventsList.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock(
  'dashboard/routes/dashboard/conversation/contact/ContactInfo.vue',
  () => ({ default: { template: '<div />' } })
);

const { getContactEvents, dispatch } = vi.hoisted(() => ({
  getContactEvents: vi.fn(),
  dispatch: vi.fn(),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getContactEvents },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({}),
    isCloudFeatureEnabled: () => false,
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: () => true,
    conversationSidebarItemsOrder: ref([{ name: 'calendar_events' }]),
    conversationSidebarVisibleItems: ref(['calendar_events']),
    toggleSidebarUIState: vi.fn(),
    isOnExpandedLayout: ref(true),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch,
    state: {
      conversationWatchers: { records: {} },
      contactConversations: { records: {} },
      contactNotes: { records: {} },
      internalTasks: { conversationRecords: {} },
    },
  }),
  useMapGetter: key =>
    ref(
      {
        getCurrentAccountId: 1,
        'accounts/isFeatureEnabledonAccount': () => true,
        getSelectedChat: { meta: { sender: { id: 7 } } },
        'conversationMetadata/getConversationMetadata': () => ({}),
      }[key]
    ),
  useFunctionGetter: key =>
    computed(() =>
      key === 'contacts/getContactById'
        ? { id: 7, name: 'Ana' }
        : { enabled: true }
    ),
}));

it('keeps the local list-save refresh of the pinned contact card in ContactPanel', async () => {
  getContactEvents.mockResolvedValueOnce({
    data: {
      payload: [
        {
          id: 'a',
          summary: 'Original',
          start: '2099-01-01T12:00:00Z',
          end: '2099-01-01T13:00:00Z',
        },
      ],
    },
  });
  const wrapper = shallowMount(ContactPanel, {
    props: { conversationId: 9 },
    global: {
      mocks: { $t: key => key },
      stubs: {
        NextAppointmentCard: false,
        'woot-feature-toggle': true,
        Draggable: {
          props: ['list'],
          template:
            '<div><slot v-for="element in list" name="item" :element="element" /></div>',
        },
        AccordionItem: { template: '<div><slot /></div>' },
      },
    },
  });
  await flushPromises();
  expect(wrapper.findComponent(NextAppointmentCard).text()).toContain(
    'Original'
  );
  getContactEvents.mockResolvedValueOnce({ data: { payload: [] } });
  wrapper
    .findComponent(CalendarEventsList)
    .vm.$emit('saved', { deleted: true });
  await flushPromises();
  expect(wrapper.findComponent(NextAppointmentCard).text()).not.toContain(
    'Original'
  );
  expect(getContactEvents).toHaveBeenCalledTimes(2);
  getContactEvents.mockResolvedValueOnce({
    data: {
      payload: [
        {
          id: 'b',
          summary: 'Remote appointment',
          start: '2099-01-02T12:00:00Z',
          end: '2099-01-02T13:00:00Z',
        },
      ],
    },
  });
  emitter.emit('calendar.events_changed', { account_id: 1, contact_ids: [7] });
  await flushPromises();
  expect(wrapper.findComponent(NextAppointmentCard).text()).toContain(
    'Remote appointment'
  );
  wrapper.unmount();
});
