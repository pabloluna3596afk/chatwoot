<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  chat: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
</script>

<template>
  <span
    v-if="chat.captain_state === 'escalated'"
    class="inline-flex items-center h-5 px-1.5 text-xs font-medium leading-none rounded-md bg-n-ruby-3 text-n-ruby-11 animate-pulse"
    data-testid="captain-state-badge"
  >
    {{ t('CONVERSATION.CARD.CAPTAIN_STATE_ESCALATED') }}
  </span>
</template>
