<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MessageApi from 'dashboard/api/inbox/message';

const props = defineProps({
  status: { type: String, required: true },
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
  canRetry: { type: Boolean, default: false },
});

const { t } = useI18n();
const isRetrying = ref(false);

const retry = async () => {
  isRetrying.value = true;
  try {
    await MessageApi.autoTranslate(props.conversationId, [props.messageId]);
  } catch {
    return;
  } finally {
    isRetrying.value = false;
  }
};
</script>

<template>
  <div
    v-if="status === 'pending'"
    class="text-xs text-n-slate-11"
    role="status"
  >
    {{ t('CONVERSATION.TRANSLATION_STATUS.PENDING') }}
  </div>
  <div
    v-else-if="status === 'failed'"
    class="flex items-center gap-2 text-xs text-n-ruby-9"
    role="status"
  >
    <span>{{ t('CONVERSATION.TRANSLATION_STATUS.FAILED') }}</span>
    <Button
      v-if="canRetry"
      intent="tertiary"
      size="xs"
      :label="t('CONVERSATION.TRANSLATION_STATUS.RETRY')"
      :is-loading="isRetrying"
      @click.stop="retry"
    />
  </div>
</template>
