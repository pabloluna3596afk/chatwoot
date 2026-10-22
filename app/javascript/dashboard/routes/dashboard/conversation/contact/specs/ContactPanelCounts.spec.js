import { vi } from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { computed, reactive, ref } from 'vue';
import ContactPanel from '../../ContactPanel.vue';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('../ContactInfo.vue', () => ({ default: { template: '<div />' } }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({}),
    isCloudFeatureEnabled: () => false,
  }),
}));
const sections = [
  'conversation_actions',
  'conversation_participants',
  'previous_conversation',
  'contact_notes',
  'internal_tasks',
  'shared_files',
];
const state = reactive({
  conversationWatchers: { records: {} },
  contactConversations: { records: {} },
  contactNotes: { records: {} },
  internalTasks: { conversationRecords: {} },
});
const senderId = ref(7);
const attachments = ref(null);
const dispatch = vi.fn();
const visible = ref([...sections]);
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: () => false,
    conversationSidebarItemsOrder: ref(sections.map(name => ({ name }))),
    conversationSidebarVisibleItems: visible,
    toggleSidebarUIState: vi.fn(),
    isOnExpandedLayout: ref(true),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ state, dispatch }),
  useMapGetter: key =>
    computed(
      () =>
        ({
          getCurrentAccountId: 1,
          getSelectedChatAttachments: attachments.value,
          getSelectedChatAttachmentsLoaded: attachments.value !== null,
          getSelectedChat: { meta: { sender: { id: senderId.value } } },
          'accounts/isFeatureEnabledonAccount': () => true,
          'conversationMetadata/getConversationMetadata': () => ({}),
        })[key]
    ),
  useFunctionGetter: key =>
    computed(() =>
      key === 'contacts/getContactById'
        ? { id: senderId.value, name: 'Ana' }
        : { enabled: false }
    ),
}));

const mountPanel = () =>
  shallowMount(ContactPanel, {
    props: { conversationId: 9 },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-feature-toggle': true,
        SidebarActionsHeader: {
          template: '<div><slot name="actions" /></div>',
        },
        Draggable: {
          props: ['list'],
          template:
            '<div><slot v-for="element in list" name="item" :element="element" /></div>',
        },
      },
    },
  });

describe('ContactPanel cached counts', () => {
  beforeEach(() => {
    visible.value = [...sections];
    senderId.value = 7;
    attachments.value = null;
    state.conversationWatchers.records = {};
    state.contactConversations.records = {};
    state.contactNotes.records = {};
    state.internalTasks.conversationRecords = {};
  });

  it('does not show invented zeroes or dispatch count requests for unloaded sections', () => {
    const wrapper = mountPanel();
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, null, null, null, null, null]);
    expect(dispatch.mock.calls.map(([action]) => action)).toEqual([
      'contacts/show',
      'attributes/get',
      'integrations/get',
    ]);
    wrapper.unmount();
  });

  it('reacts to loaded caches, includes zero and excludes the current conversation', async () => {
    const wrapper = mountPanel();
    state.conversationWatchers.records[9] = [{ id: 1 }, { id: 2 }];
    state.contactConversations.records[7] = [{ id: 9 }, { id: 10 }, { id: 11 }];
    state.contactNotes.records[7] = [];
    state.internalTasks.conversationRecords[9] = [{ id: 3 }];
    attachments.value = [
      { file_type: 'image', data_url: '/photo.png' },
      { file_type: 'file', data_url: '/doc.pdf' },
      { file_type: 'location', data_url: '/map' },
      { file_type: 'file' },
    ];
    await wrapper.vm.$nextTick();
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, 2, 2, 0, 1, 2]);
    await wrapper.setProps({ conversationId: '10' });
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, null, 2, 0, null, 2]);
    senderId.value = 8;
    attachments.value = null;
    await wrapper.vm.$nextTick();
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, null, null, null, null, null]);
    wrapper.unmount();
  });
  it('keeps actions and empty sections in their original order and respects visibility', async () => {
    state.contactNotes.records[7] = [];
    const wrapper = mountPanel();
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('title'))
    ).toEqual([
      'CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS',
      'CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE',
      'CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION',
      'CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES',
      'CONVERSATION_SIDEBAR.ACCORDION.INTERNAL_TASKS',
      'CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES',
    ]);
    expect(wrapper.find('[data-testid=conversation-now]').exists()).toBe(false);
    expect(wrapper.find('[data-testid=empty-sections]').exists()).toBe(false);
    expect(
      wrapper.findComponent({ name: 'SidebarVisibilityMenu' }).exists()
    ).toBe(true);
    visible.value = ['conversation_participants'];
    await wrapper.vm.$nextTick();
    expect(wrapper.findAllComponents(AccordionItem)).toHaveLength(1);
    wrapper.unmount();
  });
});
