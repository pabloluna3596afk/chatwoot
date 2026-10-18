<script setup>
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  loading: Boolean,
  disabled: Boolean,
  variant: {
    type: String,
    default: 'primary',
    validator: value => ['primary', 'secondary'].includes(value),
  },
  type: { type: String, default: 'button' },
});
</script>

<template>
  <button
    :type="type"
    :aria-busy="loading"
    :disabled="loading || disabled"
    class="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl px-4 py-3 text-base font-medium leading-6 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60 motion-safe:transition-colors motion-safe:duration-150 motion-reduce:[&_svg]:animate-none"
    :class="
      variant === 'primary'
        ? 'bg-n-brand text-white hover:enabled:bg-n-brand/90'
        : 'border border-solid border-n-slate-9 dark:border-n-slate-10 bg-n-solid-1 text-n-slate-12 hover:enabled:bg-n-slate-3 dark:bg-n-solid-3'
    "
  >
    <Spinner v-if="loading" :size="20" aria-hidden="true" />
    <slot />
  </button>
</template>
