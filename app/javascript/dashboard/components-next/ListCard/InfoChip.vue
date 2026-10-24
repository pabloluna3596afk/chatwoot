<script setup>
defineProps({
  tone: {
    type: String,
    default: 'neutral',
    validator: value =>
      ['neutral', 'success', 'warning', 'error'].includes(value),
  },
});

const TONE_CLASSES = {
  neutral: 'bg-n-alpha-2 text-n-slate-11',
  success: 'bg-n-teal-3 text-n-teal-11',
  warning: 'bg-n-amber-3 text-n-amber-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
};
</script>

<template>
  <span
    class="inline-flex min-w-0 items-center rounded-md px-2 py-0.5 text-xs font-medium"
    :class="TONE_CLASSES[tone]"
  >
    <slot />
  </span>
</template>
