<script setup>
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';

defineProps({
  context: { type: String, default: 'message' },
  size: { type: String, default: 'sm' },
  showLabel: { type: Boolean, default: true },
  label: { type: String, default: '' },
});
const emit = defineEmits(['insert', 'close']);
</script>

<template>
  <VariablePicker
    mode="read"
    presentation="insert"
    class="!w-auto"
    :surface="context"
    :size="size"
    :show-label="showLabel"
    :placeholder="label || $t('VARIABLES.INSERT')"
    @select="emit('insert', $event.expression)"
    @close="emit('close')"
  />
</template>
