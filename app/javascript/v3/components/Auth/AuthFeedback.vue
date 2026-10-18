<script setup>
defineProps({
  error: Boolean,
});
</script>

<template>
  <div
    :role="error ? 'alert' : 'status'"
    :aria-live="error ? 'assertive' : 'polite'"
    aria-atomic="true"
    class="flex min-w-0 items-start gap-2 rounded-xl p-3 text-sm leading-6 motion-safe:animate-fade-in-up motion-safe:[animation-duration:200ms]"
    :class="
      error ? 'bg-n-ruby-3 text-n-ruby-11' : 'bg-n-slate-3 text-n-slate-11'
    "
  >
    <span
      class="mt-1 size-4 shrink-0"
      :class="error ? 'i-lucide-circle-alert' : 'i-lucide-circle-check'"
      aria-hidden="true"
    />
    <div class="min-w-0 flex-1 break-words"><slot /></div>
  </div>
</template>
