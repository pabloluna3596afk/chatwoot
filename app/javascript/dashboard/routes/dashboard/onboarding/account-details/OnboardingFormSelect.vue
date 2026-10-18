<script setup>
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import {
  AUTH_LABEL_CLASS,
  AUTH_SELECT_TRIGGER_CLASS,
} from 'v3/components/Auth/authStyles';

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
    <p class="m-0" :class="AUTH_LABEL_CLASS">{{ label }}</p>
    <ComboBox
      v-model="model"
      :options="options"
      :aria-label="label"
      :trigger-class="AUTH_SELECT_TRIGGER_CLASS"
      :placeholder="placeholder"
      :show-search="showSearch"
      :allow-deselect="allowDeselect"
      :search-placeholder="$t('ONBOARDING_NEXT.SEARCH')"
      :empty-state="$t('ONBOARDING_NEXT.NO_RESULTS')"
      teleport
    />
  </div>
</template>
