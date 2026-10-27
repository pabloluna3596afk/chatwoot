<script setup>
defineProps({
  selected: { type: Boolean, default: false },
  action: { type: String, default: '' },
  compact: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  title: { type: String, default: '' },
});

const emit = defineEmits(['click']);
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center justify-start w-full min-w-0 text-start whitespace-nowrap transition-colors border-0 rounded-lg hover:bg-n-alpha-1 dark:hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:pointer-events-none disabled:opacity-50"
    :class="[
      compact ? 'h-7 gap-1.5 px-1.5 py-1' : 'h-8 gap-2 px-2 py-1.5',
      selected ? 'bg-n-alpha-1 dark:bg-n-solid-active' : '',
      action === 'delete' ? 'text-n-ruby-11' : 'text-n-slate-12',
    ]"
    :disabled="disabled"
    :title="title || undefined"
    @click="emit('click', $event)"
  >
    <slot />
  </button>
</template>
