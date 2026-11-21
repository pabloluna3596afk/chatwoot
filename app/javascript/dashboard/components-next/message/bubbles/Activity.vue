<script setup>
import { computed } from 'vue';
import { useActivityTime } from 'dashboard/composables/useActivityTime';
import BaseBubble from './Base.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';
import MessageSourceIndicator from '../MessageSourceIndicator.vue';
import { hasCaptainDetails } from '../helpers/captainDecision';
import { useMessageContext } from '../provider.js';
import { highlightActivityNames } from 'dashboard/helper/activityMessageHighlighter';
import { useMessageSource } from 'dashboard/composables/useMessageSource';

const { id, sender, senderType, content, createdAt, contentAttributes } =
  useMessageContext();

const { isoTime, exactTime, relativeTime } = useActivityTime(createdAt);
const { icon: sourceIcon } = useMessageSource(contentAttributes);
const displayContent = computed(() =>
  (content.value || '')
    .replace(/(?<!\.)\.(?=(?:\s|<\/[a-z][^>]*>)*\s*$)/i, '')
    .replace(/\s+(?=(?:<\/[a-z][^>]*>)*\s*$)/gi, '')
);
const highlightedContent = computed(() =>
  highlightActivityNames(
    displayContent.value,
    contentAttributes.value?.activity?.names
  )
);
const showCaptain = computed(() =>
  hasCaptainDetails({
    sender: sender?.value,
    senderType: senderType?.value,
    contentAttributes: contentAttributes.value,
  })
);
</script>

<template>
  <BaseBubble
    class="box-border mx-auto w-fit max-w-[90%] px-3 py-1 text-center leading-[1.4]"
    content-class="flex min-w-0 items-center justify-center gap-x-1.5"
    data-bubble-name="activity"
  >
    <span
      v-if="showCaptain || sourceIcon"
      class="flex size-6 shrink-0 items-center justify-center"
    >
      <CaptainGenerationDetails v-if="showCaptain" :message-id="id" />
      <MessageSourceIndicator
        v-else
        :content-attributes="contentAttributes"
        icon-class="size-4 shrink-0 text-n-slate-11"
      />
    </span>
    <span
      class="min-w-0 flex-1 text-center [overflow-wrap:anywhere]"
      data-activity-layout
    >
      <span v-dompurify-html="highlightedContent" data-activity-content />
      {{ ' ' }}
      <span aria-hidden="true" class="before:content-['\00b7']" />
      {{ ' ' }}
      <time
        v-tooltip.top="exactTime"
        :datetime="isoTime"
        :aria-label="exactTime"
        class="whitespace-nowrap text-xs text-n-slate-11"
      >
        {{ relativeTime }}
      </time>
    </span>
  </BaseBubble>
</template>
