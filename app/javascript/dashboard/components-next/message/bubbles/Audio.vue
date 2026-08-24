<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import { useMessageContext } from '../provider.js';

const { attachments } = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});
</script>

<template>
  <!--
    ponytail: force transparent outer bubble so MessageMeta doesn't sit on a
    second white strip under the audio chip (incoming looked like a white bar).
  -->
  <BaseBubble class="!bg-transparent !shadow-none" data-bubble-name="audio">
    <AudioChip
      :attachment="attachment"
      class="text-n-slate-12 skip-context-menu"
    />
  </BaseBubble>
</template>
