<script setup>
import AssistantNameText from 'dashboard/components-next/AssistantNameText.vue';
defineProps({
  heading: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <header class="flex flex-col items-start gap-2">
    <h2 class="text-n-slate-12 text-base font-medium">{{ heading }}</h2>
    <p class="text-n-slate-11 text-sm">
      <AssistantNameText :text="description" />
    </p>
  </header>
</template>
