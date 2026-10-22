<script setup>
import { computed } from 'vue';

const props = defineProps({ tools: { type: Array, required: true } });
const activeTools = computed(() =>
  props.tools.filter(tool => ['active', 'warning'].includes(tool.state))
);
const idleTools = computed(() =>
  props.tools.filter(tool => tool.state === 'idle')
);
const tones = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
};
</script>

<template>
  <div
    v-if="activeTools.length || idleTools.length"
    class="mx-3 mb-3 flex flex-col gap-2 rounded-xl border border-n-weak p-2.5"
    data-testid="contact-tools"
  >
    <button
      v-for="tool in activeTools"
      :key="tool.key"
      type="button"
      class="m-0 flex min-w-0 items-center gap-2 p-0 text-start"
      :title="tool.label"
      :aria-label="tool.label"
      :data-tool="tool.key"
      @click="tool.onClick?.()"
    >
      <span
        class="size-8 shrink-0 rounded-lg grid place-items-center"
        :class="tones[tool.state === 'warning' ? 'amber' : tool.tone]"
      >
        <span class="size-4" :class="tool.icon" />
      </span>
      <span class="text-xs text-n-slate-12 truncate" :title="tool.legend">
        {{ tool.legend }}
      </span>
    </button>
    <div
      v-if="activeTools.length && idleTools.length"
      class="border-t border-n-weak"
      data-testid="tools-separator"
    />
    <div v-if="idleTools.length" class="flex flex-wrap gap-1.5">
      <button
        v-for="tool in idleTools"
        :key="tool.key"
        type="button"
        :title="tool.label"
        :aria-label="tool.label"
        class="m-0 size-8 p-0 rounded-lg grid place-items-center bg-n-alpha-1 text-n-slate-9"
        :data-tool="tool.key"
        @click="tool.onClick?.()"
      >
        <span class="size-4" :class="tool.icon" />
      </button>
    </div>
  </div>
</template>
