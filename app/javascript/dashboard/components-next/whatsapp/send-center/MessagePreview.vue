<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
const props = defineProps({
  header: { type: String, default: '' },
  body: { type: String, default: '' },
  footer: { type: String, default: '' },
  buttons: { type: Array, default: () => [] },
  flow: { type: Boolean, default: false },
});
// Preview only: a blank line is a small gap, not a full empty line, so long messages stay compact.
const bodyLines = computed(() => props.body.split('\n'));
</script>

<template>
  <div class="min-w-0">
    <div
      class="overflow-hidden rounded-lg border border-n-weak shadow-sm bg-n-solid-1 text-n-slate-12"
      data-testid="send-center-preview"
    >
      <div
        class="px-3 py-2 flex flex-col gap-1.5 text-sm leading-5 break-words"
      >
        <div v-if="header">
          <p class="font-semibold whitespace-pre-wrap">{{ header }}</p>
        </div>
        <div data-testid="send-center-preview-body">
          <template v-for="(line, index) in bodyLines" :key="index">
            <p v-if="line" class="whitespace-pre-wrap">{{ line }}</p>
            <div v-else class="h-1.5" />
          </template>
        </div>
        <div v-if="footer">
          <p class="text-xs whitespace-pre-wrap text-n-slate-11">
            {{ footer }}
          </p>
        </div>
      </div>
      <div
        v-for="(label, index) in buttons"
        :key="index"
        class="flex items-center justify-center gap-2 px-3 py-1.5 text-sm border-t border-n-weak text-n-teal-11"
      >
        <Icon v-if="flow" icon="i-lucide-workflow" class="size-4" />
        {{ label }}
      </div>
    </div>
  </div>
</template>
