<script setup>
import { computed } from 'vue';

const props = defineProps({ category: { type: String, default: '' } });
const colors = {
  MARKETING: 'bg-n-amber-3 text-n-amber-11',
  UTILITY: 'bg-n-teal-3 text-n-teal-11',
  AUTHENTICATION: 'bg-n-iris-3 text-n-iris-11',
};
const categoryKey = computed(() => (props.category || '').toUpperCase());
const color = computed(() => colors[categoryKey.value]);
</script>

<template>
  <span
    v-if="color"
    class="inline-flex h-5 shrink-0 items-center rounded-full px-2 text-[0.6875rem] font-semibold"
    :class="color"
    :title="$t(`WHATSAPP_TEMPLATES.SEND_CENTER.CATEGORY_HELP.${categoryKey}`)"
    data-testid="template-category"
  >
    {{ $t(`WHATSAPP_TEMPLATES.SEND_CENTER.CATEGORY.${categoryKey}`) }}
  </span>
</template>
