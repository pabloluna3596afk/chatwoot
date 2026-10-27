import { computed, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLastMessage } from 'dashboard/helper/conversationHelper';

const OUTGOING_MESSAGE_TYPE = 1;

export const useCaptainState = (chat, typingUsers = computed(() => [])) => {
  const { t } = useI18n();

  const isAiAttended = computed(() => unref(chat)?.captain_state === 'ai');
  const isEscalated = computed(
    () => unref(chat)?.captain_state === 'escalated'
  );
  const assistant = computed(() => unref(chat)?.captain_assistant || null);
  const showAssistantAvatar = computed(
    () => isAiAttended.value && !!assistant.value?.name
  );

  const isWaitingForCustomer = computed(() => {
    const current = unref(chat);
    if (!isAiAttended.value || !Array.isArray(current?.messages)) return false;
    return getLastMessage(current)?.message_type === OUTGOING_MESSAGE_TYPE;
  });

  const isTyping = computed(() => {
    const currentAssistant = assistant.value;
    return (typingUsers.value || []).some(
      user =>
        user.type === 'captain_assistant' &&
        Number(user.id) === Number(currentAssistant?.id)
    );
  });

  const ringClass = computed(() =>
    isWaitingForCustomer.value ? 'ring-n-amber-9' : 'ring-n-teal-9'
  );

  const tooltip = computed(() => {
    if (!showAssistantAvatar.value) return '';
    const params = { name: assistant.value.name };
    if (isTyping.value)
      return t('CONVERSATION_SIDEBAR.TOOLS.CAPTAIN_TYPING', params);
    if (isWaitingForCustomer.value)
      return t('CONVERSATION.CARD.CAPTAIN_WAITING_CUSTOMER', params);
    return t('CONVERSATION.CARD.CAPTAIN_ASSIGNED', params);
  });

  return {
    isAiAttended,
    isEscalated,
    assistant,
    showAssistantAvatar,
    isWaitingForCustomer,
    isTyping,
    ringClass,
    tooltip,
  };
};
