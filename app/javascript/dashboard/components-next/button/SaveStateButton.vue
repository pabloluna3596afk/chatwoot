<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from './Button.vue';

const props = defineProps({
  dirty: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  invalid: { type: Boolean, default: false },
  invalidReason: { type: String, default: '' },
  labelClean: { type: String, default: '' },
  labelDirty: { type: String, default: '' },
  labelSaving: { type: String, default: '' },
  size: { type: String, default: 'sm' },
});

const emit = defineEmits(['save']);
const { t } = useI18n();

const disabled = computed(() => props.loading || !props.dirty || props.invalid);
const label = computed(() => {
  if (props.loading) return props.labelSaving || t('GENERAL.SAVE_STATE.SAVING');
  if (!props.dirty) return props.labelClean || t('GENERAL.SAVE_STATE.CLEAN');
  return props.labelDirty || t('GENERAL.SAVE_STATE.SAVE');
});
const icon = computed(() => {
  if (props.loading) return '';
  return props.dirty ? 'i-lucide-save' : 'i-lucide-check';
});
</script>

<template>
  <Button
    type="button"
    :label="label"
    :icon="icon"
    :size="size"
    :variant="dirty ? 'solid' : 'faded'"
    :color="dirty ? 'blue' : 'slate'"
    :is-loading="loading"
    :disabled="disabled"
    :aria-disabled="disabled"
    :title="invalid && dirty ? invalidReason : undefined"
    @click="!disabled && emit('save')"
  />
</template>
