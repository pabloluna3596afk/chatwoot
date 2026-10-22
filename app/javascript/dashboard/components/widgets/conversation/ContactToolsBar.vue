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
  teal: 'text-n-teal-11',
  blue: 'text-n-blue-11',
  ruby: 'text-n-ruby-11',
  iris: 'text-n-iris-11',
  amber: 'text-n-amber-11',
};
</script>

<template>
  <div
    v-if="activeTools.length || idleTools.length"
    class="mx-3 mb-3 flex flex-col gap-2"
    data-testid="contact-tools"
  >
    <button
      v-for="tool in activeTools"
      :key="tool.key"
      type="button"
      class="m-0 flex min-w-0 items-center gap-2 rounded-xl bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-11 text-start"
      :title="tool.label"
      :aria-label="tool.label"
      :data-tool="tool.key"
      @click="tool.onClick?.()"
    >
      <span
        class="size-4 shrink-0"
        :class="[
          tool.icon,
          tones[tool.state === 'warning' ? 'amber' : tool.tone],
        ]"
      />
      <span class="text-n-slate-12 truncate" :title="tool.legend">
        {{ tool.legend }}
      </span>
    </button>
    <div
      v-if="idleTools.length"
      class="flex min-h-9 items-center gap-3 rounded-xl bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-11"
      data-testid="idle-tools"
    >
      <button
        v-for="tool in idleTools"
        :key="tool.key"
        type="button"
        :title="tool.label"
        :aria-label="tool.label"
        class="m-0 flex items-center p-0 text-n-slate-9"
        :data-tool="tool.key"
        @click="tool.onClick?.()"
      >
        <span class="size-4" :class="tool.icon" />
      </button>
    </div>
  </div>
</template>
