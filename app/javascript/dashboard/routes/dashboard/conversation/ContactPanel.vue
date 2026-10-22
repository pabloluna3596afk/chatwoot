<script setup>
import { computed, watch, onMounted, ref, nextTick } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { NON_FILE_TYPES } from 'dashboard/components-next/message/constants';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import SidebarVisibilityMenu from './SidebarVisibilityMenu.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import ConversationTasksPanel from 'dashboard/components-next/InternalTasks/ConversationTasksPanel.vue';
import CalendarEventsList from 'dashboard/components/widgets/conversation/CalendarEventsList.vue';
import ContactToolsBar from 'dashboard/components/widgets/conversation/ContactToolsBar.vue';
import { useContactTools } from 'dashboard/composables/useContactTools';
import { useAppointmentEvents } from 'dashboard/composables/useAppointmentEvents';
import { useAppointmentClock } from 'dashboard/composables/useAppointmentClock';
import { useCalendarTime } from 'dashboard/composables/useCalendarTime';
import CalendarAPI from 'dashboard/api/integrations/calendar';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  conversationSidebarVisibleItems,
  isOnExpandedLayout,
} = useUISettings();

const dragging = ref(false);
const calendarEventsList = ref(null);
const calendarEventsCount = ref(null);
const revealedSections = ref([]);
// Opening from a tool must mount its content before the preferences request finishes.
const sectionOpenState = ref({});
const isSectionOpen = key =>
  sectionOpenState.value[key] ?? isContactSidebarItemOpen(key);
const toggleSection = key => {
  const isOpen = !isSectionOpen(key);
  sectionOpenState.value[key] = isOpen;
  updateUISettings({ [key]: isOpen });
};
const conversationSidebarItems = ref(conversationSidebarItemsOrder.value);

const isVisible = name =>
  conversationSidebarVisibleItems.value.includes(name) ||
  revealedSections.value.includes(name);
watch(conversationSidebarVisibleItems, visible => {
  revealedSections.value = revealedSections.value.filter(name =>
    visible.includes(name)
  );
});

const hasVisibleItems = computed(() =>
  conversationSidebarItems.value.some(item => isVisible(item.name))
);

watch(
  conversationSidebarItemsOrder,
  newOrder => {
    if (!dragging.value) {
      conversationSidebarItems.value = newOrder;
    }
  },
  { deep: true }
);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasInternalTasks = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.INTERNAL_TASKS)
);

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const calendarIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'calendars'
);

const isCalendarFeatureEnabled = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CALENDAR)
);

const isCalendarConnected = computed(
  () => calendarIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = useFunctionGetter('contacts/getContactById', contactId);
const contactAdditionalAttributes = computed(
  () =>
    contact.value.additionalAttributes ||
    contact.value.additional_attributes ||
    {}
);

// Missing cache entries are unknown, not zero. Child sections keep their existing fetches.
const participantsCount = computed(
  () =>
    store.state.conversationWatchers.records[conversationId.value]?.length ??
    null
);
const previousConversationsCount = computed(() => {
  const records = store.state.contactConversations.records[contactId.value];
  return records
    ? records.filter(item => item.id !== Number(conversationId.value)).length
    : null;
});
const contactNotesCount = computed(
  () => store.state.contactNotes.records[contactId.value]?.length ?? null
);
const internalTasksCount = computed(
  () =>
    store.state.internalTasks.conversationRecords[conversationId.value]
      ?.length ?? null
);

const attachments = useMapGetter('getSelectedChatAttachments');
const attachmentsLoaded = useMapGetter('getSelectedChatAttachmentsLoaded');
const sharedFilesCount = computed(() =>
  attachmentsLoaded.value
    ? attachments.value.filter(
        item => item.data_url && !NON_FILE_TYPES.includes(item.file_type)
      ).length
    : null
);

const contactAttributesCount = computed(() => {
  const attributes = contact.value.custom_attributes || {};
  return Object.keys(attributes).length;
});

const inbox = useFunctionGetter(
  'inboxes/getInbox',
  computed(() => props.inboxId || currentChat.value.inbox_id)
);
const { timezone, isUpcomingEvent } = useCalendarTime();
const {
  events,
  hasError,
  load: refreshAppointments,
} = useAppointmentEvents({
  context: contactId,
  contactId: () => contactId.value,
  enabled: () => isCalendarConnected.value && !!contactId.value,
  fetchEvents: signal =>
    CalendarAPI.getContactEvents(contactId.value, { signal }),
});
const now = useAppointmentClock(events, timezone);
const nextEvent = computed(
  () =>
    events.value
      .filter(event => isUpcomingEvent(event, now.value))
      .sort((a, b) => new Date(a.start) - new Date(b.start))[0]
);
const openCalendarSection = async () => {
  const wasVisible = isVisible('calendar_events');
  if (!revealedSections.value.includes('calendar_events'))
    revealedSections.value.push('calendar_events');
  const key = 'is_calendar_events_open';
  sectionOpenState.value[key] = true;
  updateUISettings({
    [key]: true,
    ...(!wasVisible && {
      conversation_sidebar_visible_items: [
        ...conversationSidebarVisibleItems.value,
        'calendar_events',
      ],
    }),
  });
  await nextTick();
};
const openCalendar = async create => {
  await openCalendarSection();
  if (create) calendarEventsList.value?.openCreate();
};
const tools = useContactTools({
  chat: currentChat,
  inboxAssistant: () => inbox.value?.captain_assistant,
  calendarConnected: isCalendarConnected,
  nextEvent,
  now,
  onOpenCalendar: openCalendar,
});

watch(conversationId, () => {
  revealedSections.value = [];
  sectionOpenState.value = {};
  calendarEventsCount.value = null;
});

const appliedContactFilter = useMapGetter('getAppliedContactFilter');

const isListScopedToContact = computed(
  () =>
    !isOnExpandedLayout.value &&
    appliedContactFilter.value?.id === contactId.value
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations so Shopify/Linear gates (panel + visibility menu) are accurate
  store.dispatch('integrations/get');
});
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    >
      <template #actions>
        <SidebarVisibilityMenu />
      </template>
    </SidebarActionsHeader>
    <div class="flex-1 min-h-0 overflow-y-auto">
      <ContactInfo :contact="contact" :channel-type="channelType" />
      <ContactToolsBar :tools="tools" />
      <div
        v-if="hasError"
        role="alert"
        class="mx-3 mb-3 text-xs text-n-ruby-11"
      >
        {{ $t('CONVERSATION_SIDEBAR.CALENDAR.LOAD_ERROR') }}
        <button
          type="button"
          class="underline"
          @click="
            refreshAppointments();
            calendarEventsList?.refresh();
          "
        >
          {{ $t('CONVERSATION_SIDEBAR.CALENDAR.RETRY') }}
        </button>
      </div>
      <div class="px-3 pb-6 list-group">
        <div
          v-if="!hasVisibleItems"
          class="flex flex-col items-center justify-center gap-2 py-8 text-center"
        >
          <span class="i-lucide-eye-off text-2xl text-n-slate-10" />
          <p class="text-sm text-n-slate-11">
            {{ $t('CONVERSATION.SIDEBAR.EMPTY_STATE') }}
          </p>
          <SidebarVisibilityMenu />
        </div>
        <Draggable
          v-else
          :list="conversationSidebarItems"
          animation="200"
          ghost-class="ghost"
          handle=".drag-handle"
          item-key="name"
          class="flex flex-col gap-3"
          @start="dragging = true"
          @end="onDragEnd"
        >
          <template #item="{ element }">
            <div
              v-if="
                element.name === 'conversation_actions' &&
                isVisible('conversation_actions')
              "
              class="conversation--actions"
            >
              <AccordionItem
                :title="
                  $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')
                "
                icon="i-lucide-bolt"
                :is-open="isSectionOpen('is_conv_actions_open')"
                compact
                @toggle="() => toggleSection('is_conv_actions_open')"
              >
                <ConversationAction
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'conversation_participants' &&
                isVisible('conversation_participants')
              "
              class="conversation--actions"
            >
              <AccordionItem
                :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
                icon="i-lucide-users"
                :count="participantsCount"
                :is-open="isSectionOpen('is_conv_participants_open')"
                compact
                @toggle="() => toggleSection('is_conv_participants_open')"
              >
                <ConversationParticipant
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'conversation_info' &&
                isVisible('conversation_info')
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
                icon="i-lucide-messages-square"
                :is-open="isSectionOpen('is_conv_details_open')"
                compact
                @toggle="() => toggleSection('is_conv_details_open')"
              >
                <ConversationInfo
                  :conversation-attributes="conversationAdditionalAttributes"
                  :contact-attributes="contactAdditionalAttributes"
                />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'contact_attributes' &&
                isVisible('contact_attributes')
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
                icon="i-lucide-contact"
                :count="contactAttributesCount"
                :is-open="isSectionOpen('is_contact_attributes_open')"
                compact
                @toggle="() => toggleSection('is_contact_attributes_open')"
              >
                <CustomAttributes
                  attribute-type="contact_attribute"
                  attribute-from="conversation_contact_panel"
                  :contact-id="contact.id"
                  :empty-state-message="
                    $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                  "
                />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'previous_conversation' &&
                isVisible('previous_conversation') &&
                !isListScopedToContact &&
                contact.id
              "
            >
              <AccordionItem
                :title="
                  $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
                "
                icon="i-lucide-history"
                :count="previousConversationsCount"
                :is-open="isSectionOpen('is_previous_conv_open')"
                compact
                @toggle="() => toggleSection('is_previous_conv_open')"
              >
                <ContactConversations
                  :contact-id="contact.id"
                  :conversation-id="conversationId"
                />
              </AccordionItem>
            </div>
            <woot-feature-toggle
              v-else-if="element.name === 'macros' && isVisible('macros')"
              feature-key="macros"
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
                icon="i-lucide-toy-brick"
                :is-open="isSectionOpen('is_macro_open')"
                compact
                @toggle="() => toggleSection('is_macro_open')"
              >
                <MacrosList :conversation-id="conversationId" />
              </AccordionItem>
            </woot-feature-toggle>
            <div
              v-else-if="
                element.name === 'linear_issues' &&
                isVisible('linear_issues') &&
                isLinearFeatureEnabled &&
                isLinearClientIdConfigured
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
                icon="i-lucide-circle-dot"
                :is-open="isSectionOpen('is_linear_issues_open')"
                compact
                @toggle="() => toggleSection('is_linear_issues_open')"
              >
                <LinearSetupCTA v-if="!isLinearConnected" />
                <LinearIssuesList v-else :conversation-id="conversationId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'calendar_events' &&
                isVisible('calendar_events') &&
                isCalendarFeatureEnabled
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CALENDAR_EVENTS')"
                icon="i-lucide-calendar"
                :count="calendarEventsCount"
                :is-open="isSectionOpen('is_calendar_events_open')"
                compact
                @toggle="() => toggleSection('is_calendar_events_open')"
              >
                <CalendarEventsList
                  v-if="isCalendarConnected"
                  ref="calendarEventsList"
                  :error-shown-elsewhere="hasError"
                  :conversation-id="conversationId"
                  :contact-id="contactId"
                  :contact-name="contact.name"
                  @saved="refreshAppointments"
                  @count-change="value => (calendarEventsCount = value)"
                />
                <p v-else class="px-4 py-3 text-sm text-n-slate-11">
                  {{ $t('CONVERSATION_SIDEBAR.CALENDAR.NOT_CONNECTED') }}
                </p>
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'shopify_orders' &&
                isVisible('shopify_orders') &&
                isShopifyFeatureEnabled
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
                icon="i-lucide-shopping-bag"
                :is-open="isSectionOpen('is_shopify_orders_open')"
                compact
                @toggle="() => toggleSection('is_shopify_orders_open')"
              >
                <ShopifyOrdersList :contact-id="contactId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'contact_notes' && isVisible('contact_notes')
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
                icon="i-lucide-notebook-pen"
                :count="contactNotesCount"
                :is-open="isSectionOpen('is_contact_notes_open')"
                compact
                @toggle="() => toggleSection('is_contact_notes_open')"
              >
                <ContactNotes :contact-id="contactId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'internal_tasks' &&
                isVisible('internal_tasks') &&
                hasInternalTasks
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.INTERNAL_TASKS')"
                icon="i-lucide-list-checks"
                :count="internalTasksCount"
                :is-open="isSectionOpen('is_internal_tasks_open')"
                compact
                @toggle="() => toggleSection('is_internal_tasks_open')"
              >
                <ConversationTasksPanel :conversation-id="conversationId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'shared_files' && isVisible('shared_files')
              "
            >
              <AccordionItem
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
                icon="i-lucide-paperclip"
                :count="sharedFilesCount"
                :is-open="isSectionOpen('is_shared_files_open')"
                compact
                @toggle="() => toggleSection('is_shared_files_open')"
              >
                <SharedFiles />
              </AccordionItem>
            </div>
          </template>
        </Draggable>
      </div>
    </div>
  </div>
</template>
