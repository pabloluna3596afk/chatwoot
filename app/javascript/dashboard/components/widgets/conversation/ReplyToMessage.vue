<script setup>
import ReplyPreview from 'next/message/ReplyPreview.vue';

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
  inboxId: { type: Number, default: null },
});

const emit = defineEmits(['dismiss']);
</script>

<template>
  <div
    class="reply-editor flex min-w-0 items-center overflow-hidden rounded-t-2xl rounded-b-none bg-n-alpha-1"
  >
    <ReplyPreview
      :message="message"
      :current-user-id="currentUserId"
      :conversation-id="conversationId"
      :inbox-id="inboxId"
      composer
    />
    <button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      type="button"
      :aria-label="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      class="grid w-12 shrink-0 cursor-pointer self-stretch place-items-center bg-transparent text-n-slate-11 outline-none transition-colors hover:text-n-slate-12 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
      @click.stop="emit('dismiss')"
    >
      <span class="i-lucide-x size-4" aria-hidden="true" />
    </button>
  </div>
</template>
