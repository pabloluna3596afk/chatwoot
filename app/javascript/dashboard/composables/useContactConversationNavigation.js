import { useMapGetter, useStore } from 'dashboard/composables/store';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import wootConstants from 'dashboard/constants/globals';
import { useConversationRoutePath } from './useConversationRoutePath';

// Resolves the conversations before and after the active one in the contact's history.
export function useContactConversationNavigation() {
  const store = useStore();
  const route = useRoute();
  const { buildConversationPath } = useConversationRoutePath();

  const currentChat = useMapGetter('getSelectedChat');
  const neighbours = useMapGetter(
    'contactConversations/getConversationNeighbours'
  );
  const appliedContactFilter = useMapGetter('getAppliedContactFilter');

  const filteredConversations = useMapGetter('getFilteredConversations');
  const replyOpenedFor = ref(null);

  const contactId = computed(() => currentChat.value?.meta?.sender?.id);

  // The inbox view has no list to scope, so a filter left behind there means nothing.
  const isReviewingHistory = computed(
    () =>
      !String(route.name || '').startsWith('inbox_view') &&
      appliedContactFilter.value?.id === contactId.value
  );

  // The server returns the open conversation between its neighbours.
  const orderedConversations = computed(() =>
    [...neighbours.value(currentChat.value?.id)].sort(
      (a, b) => a.created_at - b.created_at || a.id - b.id
    )
  );

  const currentIndex = computed(() =>
    orderedConversations.value.findIndex(
      conversation => conversation.id === currentChat.value?.id
    )
  );

  // The history view lists newest first, so its head is the latest conversation.
  const latestConversation = computed(() =>
    isReviewingHistory.value ? (filteredConversations.value[0] ?? null) : null
  );
  // The window decides once loaded; until then the head of the history list stands in.
  const isLatestConversation = computed(() =>
    currentIndex.value >= 0
      ? currentIndex.value === orderedConversations.value.length - 1
      : latestConversation.value?.id === currentChat.value?.id
  );

  // Moving forward is a review move; on a live chat it pulls the agent off the open one.
  const canMoveForward = computed(
    () =>
      appliedContactFilter.value?.id === contactId.value ||
      currentChat.value?.status === wootConstants.STATUS_TYPE.RESOLVED
  );

  const olderConversation = computed(() =>
    currentIndex.value > 0
      ? orderedConversations.value[currentIndex.value - 1]
      : null
  );

  const newerConversation = computed(() =>
    canMoveForward.value && currentIndex.value >= 0
      ? (orderedConversations.value[currentIndex.value + 1] ?? null)
      : null
  );

  const isReplyRevealed = computed(
    () => replyOpenedFor.value === currentChat.value?.id
  );
  const isReadingHistory = computed(
    () =>
      isReviewingHistory.value &&
      !isLatestConversation.value &&
      !isReplyRevealed.value
  );
  const leaveReadingMode = () => {
    replyOpenedFor.value = currentChat.value?.id;
  };

  watch(
    [contactId, () => currentChat.value?.id],
    ([id, conversationId]) => {
      replyOpenedFor.value = null;
      if (!id || !conversationId) return;

      store.dispatch('contactConversations/getNeighbours', {
        contactId: id,
        conversationId,
      });
    },
    { immediate: true }
  );

  return {
    olderConversation,
    newerConversation,
    buildConversationPath,
    isReadingHistory,
    latestConversation,
    leaveReadingMode,
  };
}
