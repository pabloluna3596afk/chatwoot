<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  name: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  loading: {
    type: Boolean,
    default: false,
  },
  activateLabel: {
    type: String,
    required: true,
  },
});

defineEmits(['activate']);
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-2 rounded-md border border-n-weak bg-n-solid-1 p-3"
  >
    <div>
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{ name }}
      </p>
      <p v-if="description" class="mb-0 mt-1 text-xs text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <Button
      sm
      faded
      icon="i-lucide-sparkles"
      :label="activateLabel"
      :is-loading="loading"
      @click="$emit('activate')"
    />
  </div>
</template>
