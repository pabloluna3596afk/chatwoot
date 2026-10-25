<script setup>
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';
import TemplatesCreateButton from './TemplatesCreateButton.vue';

defineProps({
  placeholder: { type: String, required: true },
  primaryAction: { type: Object, default: null },
});
const search = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
    <div class="flex flex-wrap items-center gap-2 min-w-0">
      <SearchInput
        v-model="search"
        size="sm"
        :placeholder="placeholder"
        :aria-label="placeholder"
        class="w-56"
      />
      <slot name="filters" />
    </div>
    <div class="flex items-center gap-2 ms-auto shrink-0">
      <slot name="actions" />
      <TemplatesCreateButton v-if="primaryAction" :action="primaryAction" />
    </div>
  </div>
</template>
