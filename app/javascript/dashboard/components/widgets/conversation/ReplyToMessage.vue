<script setup>
import ReplyPreview from 'next/message/ReplyPreview.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['dismiss']);
</script>

<template>
  <div class="reply-editor mt-2 flex w-full min-w-0 items-start gap-1.5">
    <ReplyPreview
      :message="message"
      composer
      class="flex-1"
      :aria-label="$t('CONVERSATION.REPLYBOX.REPLYING_TO')"
    />
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      :aria-label="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      intent="tertiary"
      size="xs"
      icon="i-lucide-x"
      class="shrink-0 !size-6 focus-visible:ring-2 focus-visible:ring-n-brand"
      @click.stop="emit('dismiss')"
    />
  </div>
</template>
