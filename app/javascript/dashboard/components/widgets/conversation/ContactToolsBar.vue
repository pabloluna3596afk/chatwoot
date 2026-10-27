<script setup>
import { computed } from 'vue';
import TypingDots from './TypingDots.vue';

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
    class="mx-3 mb-3 flex flex-col gap-1.5 rounded-xl bg-n-alpha-1 px-3 py-2"
    data-testid="contact-tools"
  >
    <component
      :is="tool.onClick ? 'button' : 'div'"
      v-for="tool in activeTools"
      :key="tool.key"
      :type="tool.onClick ? 'button' : undefined"
      class="m-0 flex min-h-11 w-full min-w-0 items-center gap-2 text-sm text-start"
      :title="tool.label"
      :aria-label="tool.label"
      :role="tool.key === 'captain' && !tool.onClick ? 'status' : undefined"
      :data-tool="tool.key"
      @click="tool.onClick?.()"
    >
      <img
        v-if="
          tool.key === 'captain' &&
          tool.assistantAvatar &&
          tool.state !== 'warning'
        "
        :src="tool.assistantAvatar"
        alt=""
        class="size-4 shrink-0 rounded-full object-cover"
      />
      <span
        v-if="
          tool.key !== 'captain' ||
          !tool.assistantAvatar ||
          tool.state === 'warning'
        "
        class="size-4 shrink-0"
        :class="[
          tool.icon,
          tones[tool.state === 'warning' ? 'amber' : tool.tone],
        ]"
      />
      <span class="min-w-0 text-n-slate-12" :title="tool.label">
        {{ tool.legend }}
      </span>
      <TypingDots v-if="tool.isTyping" class="text-n-teal-11" />
    </component>
    <div
      v-if="activeTools.length && idleTools.length"
      class="border-t border-n-weak"
      data-testid="tools-separator"
    />
    <div
      v-if="idleTools.length"
      class="flex min-h-6 items-center gap-3"
      data-testid="idle-tools"
    >
      <button
        v-for="tool in idleTools"
        :key="tool.key"
        type="button"
        :title="tool.label"
        :aria-label="tool.label"
        class="m-0 flex min-h-11 min-w-0 items-center gap-2 p-0 text-start"
        :data-tool="tool.key"
        @click="tool.onClick?.()"
      >
        <span class="size-4 shrink-0 text-n-slate-9" :class="tool.icon" />
        <span v-if="idleTools.length === 1" class="text-sm text-n-slate-11">
          {{ tool.label }}
        </span>
      </button>
    </div>
  </div>
</template>
