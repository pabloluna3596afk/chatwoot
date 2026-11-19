<script setup>
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  duration: { type: String, default: '00:00' },
  playStopIcon: { type: String, required: true },
  sendLabel: { type: String, required: true },
  sendDisabled: { type: Boolean, default: false },
  isNote: { type: Boolean, default: false },
});
defineEmits(['cancel', 'playPause', 'send']);
</script>

<template>
  <div class="flex w-full items-center gap-2 px-2.5 py-1.5">
    <NextButton
      intent="tertiary"
      sm
      icon="i-lucide-trash-2"
      :aria-label="$t('CONVERSATION.REPLYBOX.CANCEL_RECORDING')"
      @click="$emit('cancel')"
    />
    <span
      class="size-2 shrink-0 rounded-full bg-n-ruby-9 motion-safe:animate-pulse"
    />
    <span class="sr-only" aria-live="polite">{{
      $t('CONVERSATION.REPLYBOX.RECORDING')
    }}</span>
    <span class="tabular-nums text-sm text-n-slate-12">{{ duration }}</span>
    <NextButton
      intent="tertiary"
      sm
      :icon="playStopIcon"
      :aria-label="duration"
      @click="$emit('playPause')"
    />
    <span class="flex-1" />
    <NextButton
      intent="primary"
      :color="isNote ? 'amber' : undefined"
      sm
      icon="i-lucide-send-horizontal"
      :aria-label="sendLabel"
      :disabled="sendDisabled"
      class="max-md:!rounded-full max-md:!size-8 max-md:!p-0"
      @click="$emit('send')"
    >
      <span class="max-md:hidden">{{ sendLabel }}</span>
    </NextButton>
  </div>
</template>
