<script setup>
import ReplyPreview from 'next/message/ReplyPreview.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  message: {
    type: Object,
    required: true,
  },
  currentUserId: {
    type: Number,
    default: null,
  },
  conversationId: { type: Number, default: null },
});

const emit = defineEmits(['dismiss']);
</script>

<template>
  <div
    class="reply-editor flex min-w-0 items-center overflow-hidden rounded-t-2xl rounded-b-none bg-n-alpha-1 pe-2"
  >
    <ReplyPreview
      :message="message"
      :current-user-id="currentUserId"
      :conversation-id="conversationId"
      composer
    />
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      :aria-label="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      intent="tertiary"
      size="xs"
      icon="i-lucide-x"
      class="!size-6 shrink-0 focus-visible:ring-2 focus-visible:ring-n-brand"
      @click.stop="emit('dismiss')"
    />
  </div>
</template>
