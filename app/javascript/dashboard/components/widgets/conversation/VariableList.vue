<script setup>
import VariablePicker from 'dashboard/components-next/variable-picker/VariablePicker.vue';

defineProps({
  caretPosition: { type: Object, default: null },
  searchKey: { type: String, default: '' },
  context: { type: String, default: 'message' },
});
const emit = defineEmits(['selectVariable', 'close', 'removeTrigger']);
</script>

<template>
  <VariablePicker
    mode="read"
    presentation="caret"
    :surface="context"
    :caret-position="caretPosition"
    :search-key="searchKey"
    @select="emit('selectVariable', $event.expression.slice(3, -3))"
    @close="emit('close')"
    @remove-trigger="emit('removeTrigger')"
  />
</template>
