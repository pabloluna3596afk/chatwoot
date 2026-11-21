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
  <div class="reply-editor relative w-full min-w-0 rounded-t-2xl bg-n-alpha-1">
    <ReplyPreview
      :message="message"
      composer
      class="!rounded-t-2xl !rounded-b-none !bg-transparent !pe-10"
      :aria-label="$t('CONVERSATION.REPLYBOX.REPLYING_TO')"
    />
    <Button
      v-tooltip="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      :aria-label="$t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      intent="tertiary"
      size="xs"
      icon="i-lucide-x"
      class="absolute top-2 end-2 !size-6 focus-visible:ring-2 focus-visible:ring-n-brand"
      @click.stop="emit('dismiss')"
    />
  </div>
</template>
