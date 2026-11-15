<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const props = defineProps({
  summaryLines: { type: Array, default: () => [] },
});

const { content, contentAttributes, sender } = useMessageContext();
const { t, te } = useI18n();
const assistantName = computed(
  () => sender.value?.name || t('CONVERSATION.BOT_HANDOFF_FALLBACK_ASSIGNEE')
);
const reasonKey = computed(() => {
  const category = contentAttributes.value.captainHandoff.reasonCategory;
  const key = `CONVERSATION.CAPTAIN_HANDOFF.REASON.${category}`;
  return te(key) ? key : 'CONVERSATION.CAPTAIN_HANDOFF.REASON.unknown';
});
const visibleSummaryLines = computed(() => props.summaryLines.slice(0, 3));
</script>

<template>
  <BaseBubble class="px-3 py-2" data-bubble-name="captain-handoff">
    <div class="flex flex-col gap-2">
      <div class="flex flex-wrap gap-2">
        <span
          class="flex items-center gap-1 text-sm font-medium text-n-amber-12"
        >
          <span class="i-lucide-user-round-check size-4 shrink-0" />
          {{ t('CONVERSATION.CAPTAIN_HANDOFF.TITLE', { name: assistantName }) }}
        </span>
        <span
          class="rounded-full border border-n-amber-6 bg-n-amber-2 px-2 py-0.5 text-xs text-n-amber-11"
        >
          {{ t(reasonKey) }}
        </span>
      </div>
      <p class="m-0 whitespace-pre-wrap text-sm text-n-slate-12">
        {{ content }}
      </p>
      <ul
        v-if="visibleSummaryLines.length"
        class="m-0 list-disc ps-4 text-sm text-n-slate-12"
      >
        <li v-for="(line, index) in visibleSummaryLines" :key="index">
          {{ line }}
        </li>
      </ul>
    </div>
  </BaseBubble>
</template>
