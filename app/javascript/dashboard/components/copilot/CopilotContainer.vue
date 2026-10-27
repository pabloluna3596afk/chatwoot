<script setup>
import {
  ref,
  computed,
  onMounted,
  watch,
  nextTick,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Copilot from 'dashboard/components-next/copilot/Copilot.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { emitter } from 'shared/helpers/mitt';
import CopilotActionItemsAPI from 'dashboard/api/captain/copilotActionItems';

const store = useStore();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const { isEnterprise } = useConfig();
const currentUser = useMapGetter('getCurrentUser');
const assistants = useMapGetter('captainAssistants/getRecords');
const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const inboxAssistant = useMapGetter('getCopilotAssistant');
const currentChat = useMapGetter('getSelectedChat');
const lastPublicMessage = useMapGetter('getLastEmailInSelectedChat');
const currentAccountId = useMapGetter('getCurrentAccountId');
const labels = useMapGetter('labels/getLabels');
const agents = useMapGetter('agents/getVerifiedAgents');
const teams = useMapGetter('teams/getTeams');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const selectedCopilotThreadId = ref(
  uiSettings.value.copilot_active_thread_id || null
);
const threads = ref([]);
const isHistoryOpen = ref(false);
const isLoadingHistory = ref(false);
const historyPage = ref(1);
const hasMoreHistory = ref(false);
const actionItems = ref([]);
const unreadCount = ref(uiSettings.value.copilot_unread_count || 0);

const messages = computed(() =>
  store.getters['copilotMessages/getMessagesByThreadId'](
    selectedCopilotThreadId.value
  )
);
const canSuggestReply = computed(
  () => lastPublicMessage.value?.message_type === MESSAGE_TYPE.INCOMING
);
const activeAssistant = computed(() => {
  const preferredId = uiSettings.value.preferred_captain_assistant_id;
  if (preferredId) {
    const preferredAssistant = assistants.value.find(a => a.id === preferredId);
    if (preferredAssistant) return preferredAssistant;
  }
  if (inboxAssistant.value) {
    const inboxMatchedAssistant = assistants.value.find(
      a => a.id === inboxAssistant.value.id
    );
    if (inboxMatchedAssistant) return inboxMatchedAssistant;
  }
  return assistants.value[0];
});
const isOpen = computed(() => !!uiSettings.value.is_copilot_panel_open);
const shouldShowCopilotPanel = computed(() => {
  if (!isEnterprise) return false;
  const enabled = isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN
  );
  return enabled && isOpen.value && !uiFlags.value.fetchingList;
});
const contextName = computed(
  () =>
    currentChat.value?.meta?.sender?.name ||
    currentChat.value?.contact?.name ||
    currentChat.value?.sender?.name ||
    ''
);

const persistThread = threadId => {
  selectedCopilotThreadId.value = threadId;
  actionItems.value = [];
  updateUISettings({ copilot_active_thread_id: threadId });
};
const loadActionItems = async threadId => {
  if (!threadId) {
    actionItems.value = [];
    return;
  }
  try {
    const { data } = await CopilotActionItemsAPI.get(threadId);
    if (Number(threadId) === Number(selectedCopilotThreadId.value))
      actionItems.value = data;
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
  }
};
const upsertActionItem = item => {
  if (Number(item.copilot_thread_id) !== Number(selectedCopilotThreadId.value))
    return;
  const index = actionItems.value.findIndex(
    existing => existing.id === item.id
  );
  if (index === -1) actionItems.value.push(item);
  else actionItems.value[index] = item;
};
const handleActionItemEvent = item => upsertActionItem(item);
const updateActionItem = async ({ id, payload }) => {
  try {
    const { data } = await CopilotActionItemsAPI.update(id, payload);
    upsertActionItem(data);
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
  }
};
const decideActionItem = async (id, decision) => {
  try {
    const { data } =
      decision === 'approve'
        ? await CopilotActionItemsAPI.approve(id)
        : await CopilotActionItemsAPI.reject(id);
    upsertActionItem(data);
  } catch (_error) {
    if (_error.response?.data?.id) upsertActionItem(_error.response.data);
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
    await loadActionItems(selectedCopilotThreadId.value);
  }
};
const setAssistant = async assistant => {
  await updateUISettings({ preferred_captain_assistant_id: assistant.id });
};
const minimize = async () => {
  updateUISettings({ is_copilot_panel_open: false });
  await nextTick();
  document.getElementById('copilot-launcher-button')?.focus();
};
const newChat = () => {
  persistThread(null);
  isHistoryOpen.value = false;
};
const loadHistory = async () => {
  isLoadingHistory.value = true;
  try {
    historyPage.value = 1;
    threads.value = await store.dispatch('copilotThreads/get', {
      page: historyPage.value,
    });
    hasMoreHistory.value = threads.value.length === 5;
    isHistoryOpen.value = true;
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
  } finally {
    isLoadingHistory.value = false;
  }
};
const loadMoreHistory = async () => {
  if (isLoadingHistory.value || !hasMoreHistory.value) return;
  isLoadingHistory.value = true;
  try {
    historyPage.value += 1;
    const nextPage = await store.dispatch('copilotThreads/get', {
      page: historyPage.value,
    });
    threads.value = [...threads.value, ...nextPage];
    hasMoreHistory.value = nextPage.length === 5;
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
  } finally {
    isLoadingHistory.value = false;
  }
};
const selectThread = async thread => {
  try {
    await store.dispatch('copilotMessages/get', thread.id);
    persistThread(thread.id);
    await loadActionItems(thread.id);
    isHistoryOpen.value = false;
    unreadCount.value = 0;
    updateUISettings({ copilot_unread_count: 0 });
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
  }
};
const sendMessage = async payload => {
  const message = typeof payload === 'string' ? payload : payload.message;
  const requestType =
    typeof payload === 'string' ? undefined : payload.requestType;
  try {
    if (selectedCopilotThreadId.value) {
      await store.dispatch('copilotMessages/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: currentChat.value?.id,
        threadId: selectedCopilotThreadId.value,
        message,
      });
    } else {
      const response = await store.dispatch('copilotThreads/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: currentChat.value?.id,
        message,
        ...(requestType && { request_type: requestType }),
      });
      persistThread(response.id);
      await loadActionItems(response.id);
      threads.value = [
        response,
        ...threads.value.filter(thread => thread.id !== response.id),
      ];
    }
    return true;
  } catch (_error) {
    useAlert(t('CAPTAIN.COPILOT.ERROR'));
    return false;
  }
};
const handleKeydown = event => {
  if (event.key === 'Escape' && isOpen.value) minimize();
};

watch(
  () =>
    messages.value.filter(message => message.message_type === 'assistant')
      .length,
  (count, previousCount) => {
    if (!isOpen.value && count > previousCount) {
      unreadCount.value += count - previousCount;
      updateUISettings({ copilot_unread_count: unreadCount.value });
    }
  }
);
watch(isOpen, open => {
  if (open) {
    unreadCount.value = 0;
    updateUISettings({ copilot_unread_count: 0 });
  }
});

onMounted(async () => {
  window.addEventListener('keydown', handleKeydown);
  if (isEnterprise) {
    try {
      await store.dispatch('captainAssistants/get');
      if (selectedCopilotThreadId.value) {
        await store.dispatch(
          'copilotMessages/get',
          selectedCopilotThreadId.value
        );
        await loadActionItems(selectedCopilotThreadId.value);
      }
    } catch (_error) {
      useAlert(t('CAPTAIN.COPILOT.ERROR'));
    }
  }
});
onMounted(() => {
  emitter.on('copilot_action_item_changed', handleActionItemEvent);
  store.dispatch('labels/get');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
});
onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown);
  emitter.off('copilot_action_item_changed', handleActionItemEvent);
});
</script>

<template>
  <Transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="scale-95 opacity-0"
    enter-to-class="scale-100 opacity-100"
    leave-active-class="transition duration-150 ease-in"
    leave-from-class="scale-100 opacity-100"
    leave-to-class="scale-95 opacity-0"
  >
    <section
      v-if="shouldShowCopilotPanel"
      role="dialog"
      aria-modal="false"
      :aria-label="t('CAPTAIN.COPILOT.TITLE')"
      class="fixed z-40 flex flex-col overflow-hidden border border-n-weak bg-n-surface-2 shadow-2xl ltr:right-4 rtl:left-4 bottom-20 h-[min(600px,calc(100dvh-6rem))] w-[min(380px,calc(100vw-2rem))] rounded-2xl ltr:origin-bottom-right rtl:origin-bottom-left max-sm:inset-0 max-sm:h-[100dvh] max-sm:w-full max-sm:rounded-none max-sm:pb-[env(safe-area-inset-bottom)]"
    >
      <Copilot
        :messages="messages"
        :support-agent="currentUser"
        :assistants="assistants"
        :active-assistant="activeAssistant"
        :can-suggest-reply="canSuggestReply"
        :on-send-message="sendMessage"
        :threads="threads"
        :is-history-open="isHistoryOpen"
        :is-loading-history="isLoadingHistory"
        :has-more-history="hasMoreHistory"
        :context-id="currentChat?.id"
        :context-name="contextName"
        :action-items="actionItems"
        :action-labels="labels"
        :action-agents="agents"
        :action-teams="teams"
        @approve-action="decideActionItem($event, 'approve')"
        @reject-action="decideActionItem($event, 'reject')"
        @edit-action="updateActionItem"
        @set-assistant="setAssistant"
        @reset="newChat"
        @new-chat="newChat"
        @open-history="loadHistory"
        @load-more-history="loadMoreHistory"
        @close-history="isHistoryOpen = false"
        @select-thread="selectThread"
        @minimize="minimize"
      />
    </section>
  </Transition>
</template>
