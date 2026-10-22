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
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
const sections = [
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
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: () => false,
    conversationSidebarItemsOrder: ref(sections.map(name => ({ name }))),
    conversationSidebarVisibleItems: ref(sections),
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
    ).toEqual([null, null, null, null, null]);
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
    ).toEqual([2, 2, 0, 1, 2]);
    await wrapper.setProps({ conversationId: '10' });
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, 2, 0, null, 2]);
    senderId.value = 8;
    attachments.value = null;
    await wrapper.vm.$nextTick();
    expect(
      wrapper.findAllComponents(AccordionItem).map(item => item.props('count'))
    ).toEqual([null, null, null, null, null]);
    wrapper.unmount();
  });
});
