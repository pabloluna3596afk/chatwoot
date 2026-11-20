<script setup>
import { computed } from 'vue';
import { useActivityTime } from 'dashboard/composables/useActivityTime';
import BaseBubble from './Base.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';
import { hasCaptainDetails } from '../helpers/captainDecision';
import { useMessageContext } from '../provider.js';

const { id, sender, senderType, content, createdAt, contentAttributes } =
  useMessageContext();

const { isoTime, exactTime, relativeTime } = useActivityTime(createdAt);
const showCaptain = computed(() =>
  hasCaptainDetails({
    sender: sender?.value,
    senderType: senderType?.value,
    contentAttributes: contentAttributes.value,
  })
);
</script>

<template>
  <BaseBubble class="text-center leading-5" data-bubble-name="activity">
    <span v-dompurify-html="content" />
    {{ ' ' }}
    <time
      v-tooltip.top="exactTime"
      :datetime="isoTime"
      :aria-label="exactTime"
      class="text-xs text-n-slate-11"
      >{{ relativeTime }}</time
    >
    {{ ' ' }}
    <CaptainGenerationDetails v-if="showCaptain" :message-id="id" />
  </BaseBubble>
</template>
