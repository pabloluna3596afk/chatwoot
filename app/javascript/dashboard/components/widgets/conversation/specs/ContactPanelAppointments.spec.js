import { vi } from 'vitest';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import ContactToolsBar from '../ContactToolsBar.vue';
import CalendarEventsList from '../CalendarEventsList.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock(
  'dashboard/routes/dashboard/conversation/contact/ContactInfo.vue',
  () => ({ default: { template: '<div />' } })
);

const visible = ref(['calendar_events']);

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
    isContactSidebarItemOpen: () => false,
    conversationSidebarItemsOrder: ref([{ name: 'calendar_events' }]),
    conversationSidebarVisibleItems: visible,
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

it('refreshes the contact tool after local saves and remote appointment changes', async () => {
  visible.value = ['calendar_events'];
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
  expect(
    wrapper.findComponent(ContactToolsBar).props('tools')[1].legend
  ).toContain('Original');
  getContactEvents.mockResolvedValueOnce({ data: { payload: [] } });
  wrapper
    .findComponent(CalendarEventsList)
    .vm.$emit('saved', { deleted: true });
  await flushPromises();
  expect(
    wrapper.findComponent(ContactToolsBar).props('tools')[1].legend
  ).not.toContain('Original');
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
  expect(
    wrapper.findComponent(ContactToolsBar).props('tools')[1].legend
  ).toContain('Remote appointment');
  wrapper.unmount();
});

it('opens the calendar and its creation flow immediately while preferences are still saving', async () => {
  visible.value = [];
  getContactEvents.mockResolvedValue({ data: { payload: [] } });
  const openCreate = vi.fn();
  const wrapper = shallowMount(ContactPanel, {
    props: { conversationId: 9 },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-feature-toggle': true,
        Draggable: {
          props: ['list'],
          template:
            '<div><slot v-for="element in list" name="item" :element="element" /></div>',
        },
        AccordionItem: false,
        CalendarEventsList: { template: '<div />', methods: { openCreate } },
      },
    },
  });
  await flushPromises();
  expect(wrapper.findComponent(CalendarEventsList).exists()).toBe(false);
  const calendarTool = wrapper.findComponent(ContactToolsBar).props('tools')[1];
  expect(calendarTool.state).toBe('idle');
  await calendarTool.onClick();
  expect(wrapper.findComponent(CalendarEventsList).exists()).toBe(true);
  expect(openCreate).toHaveBeenCalledOnce();
  await wrapper.find('.drag-handle').trigger('click');
  expect(wrapper.findComponent(CalendarEventsList).exists()).toBe(false);
  wrapper.unmount();
});
