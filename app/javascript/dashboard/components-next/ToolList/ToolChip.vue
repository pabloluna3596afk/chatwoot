<script setup>
import { computed } from 'vue';

const props = defineProps({
  tone: {
    type: String,
    default: 'neutral',
    validator: value => ['neutral', 'amber', 'teal', 'ruby'].includes(value),
  },
});

const toneClasses = computed(
  () =>
    ({
      neutral: 'bg-n-alpha-2 text-n-slate-11',
      amber: 'bg-n-amber-3 text-n-amber-11',
      teal: 'bg-n-teal-3 text-n-teal-11',
      ruby: 'bg-n-ruby-3 text-n-ruby-11',
    })[props.tone]
);
</script>

<template>
  <span
    class="inline-flex max-w-full items-center rounded-md px-2 py-0.5 text-xs font-medium"
    :class="toneClasses"
  >
    <slot />
  </span>
</template>
