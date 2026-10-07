<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ summary: { type: Object, required: true } });
defineEmits(['details']);
const { t } = useI18n();
const tones = {
  published: 'bg-n-teal-3 text-n-teal-11',
  partial: 'bg-n-amber-3 text-n-amber-11',
  error: 'bg-n-ruby-3 text-n-ruby-11',
  none: 'bg-n-alpha-2 text-n-slate-11',
};
const label = computed(() =>
  t(`WHATSAPP_FLOWS.META.SUMMARY.${props.summary.state}`, {
    published: props.summary.published,
    total: props.summary.total,
    count: props.summary.errors,
  })
);
</script>

<template>
  <Button
    type="button"
    ghost
    slate
    sm
    no-animation
    trailing-icon
    icon="i-lucide-chevron-right"
    :label="label"
    :aria-label="$t('WHATSAPP_FLOWS.META.DETAIL.OPEN', { status: label })"
    :class="tones[summary.state]"
    class="!px-2 !py-1 !rounded-full !outline-0 whitespace-nowrap"
    :data-state="summary.state"
    data-testid="flow-publication-summary"
    @click="$emit('details')"
  />
</template>
