<script setup>
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

defineProps({
  label: { type: String, required: true },
  options: { type: Array, required: true },
  placeholder: { type: String, required: true },
  showSearch: Boolean,
  allowDeselect: Boolean,
});
const model = defineModel({ type: String, required: true });
</script>

<template>
  <div class="space-y-2">
    <p class="m-0 text-sm font-medium text-n-slate-12">{{ label }}</p>
    <ComboBox
      v-model="model"
      :options="options"
      :aria-label="label"
      :placeholder="placeholder"
      :show-search="showSearch"
      :allow-deselect="allowDeselect"
      :search-placeholder="$t('ONBOARDING_NEXT.SEARCH')"
      :empty-state="$t('ONBOARDING_NEXT.NO_RESULTS')"
      teleport
      class="[&>div>button]:!h-14 [&>div>button]:!rounded-full [&>div>button]:!px-5 [&>div>button]:!text-base [&>div>button]:bg-n-solid-1 [&>div>button]:dark:bg-n-solid-3"
    />
  </div>
</template>
