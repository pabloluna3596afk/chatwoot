import { computed, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLastMessage } from 'dashboard/helper/conversationHelper';

const OUTGOING_MESSAGE_TYPE = 1;

export const useCaptainState = chat => {
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

  const ringClass = computed(() =>
    isWaitingForCustomer.value ? 'ring-n-amber-9' : 'ring-n-teal-9'
  );

  const tooltip = computed(() => {
    if (!showAssistantAvatar.value) return '';
    const key = isWaitingForCustomer.value
      ? 'CONVERSATION.CARD.CAPTAIN_WAITING_CUSTOMER'
      : 'CONVERSATION.CARD.CAPTAIN_ANSWERING';
    return t(key, { name: assistant.value.name });
  });

  return {
    isAiAttended,
    isEscalated,
    assistant,
    showAssistantAvatar,
    isWaitingForCustomer,
    ringClass,
    tooltip,
  };
};
