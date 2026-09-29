<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  chat: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const BASE_CLASS =
  'inline-flex items-center h-5 px-1.5 text-xs font-medium leading-none rounded-md';
</script>

<template>
  <span
    v-if="chat.captain_state === 'ai'"
    class="bg-n-teal-3 text-n-teal-11"
    :class="[BASE_CLASS]"
    data-testid="captain-state-badge"
  >
    {{ t('CONVERSATION.CARD.CAPTAIN_STATE_AI') }}
  </span>
  <span
    v-else-if="chat.captain_state === 'escalated'"
    class="bg-n-ruby-3 text-n-ruby-11"
    :class="[BASE_CLASS]"
    data-testid="captain-state-badge"
  >
    {{ t('CONVERSATION.CARD.CAPTAIN_STATE_ESCALATED') }}
  </span>
</template>
