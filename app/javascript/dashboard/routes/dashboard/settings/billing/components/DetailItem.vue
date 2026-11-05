<script setup>
defineProps({
  label: {
    type: String,
    required: true,
  },
  value: {
    type: String,
    required: true,
  },
});
</script>

<template>
  <div class="min-w-0 px-5">
    <span class="text-n-slate-11 text-xs">
      {{ label }}
    </span>
    <div class="mt-2 break-words text-xl font-medium text-n-slate-12">
      {{ value }}
    </div>
  </div>
</template>
