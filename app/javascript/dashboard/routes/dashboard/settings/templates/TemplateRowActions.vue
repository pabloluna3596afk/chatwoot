<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  canManage: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
  labels: { type: Object, required: true },
});
const emit = defineEmits(['edit', 'duplicate', 'delete']);
const buttonProps = Object.freeze({
  variant: 'outline',
  color: 'slate',
  size: 'sm',
  type: 'button',
});
const actions = [
  { key: 'edit', run: () => emit('edit'), icon: 'i-lucide-pencil' },
  { key: 'duplicate', run: () => emit('duplicate'), icon: 'i-lucide-copy' },
  { key: 'delete', run: () => emit('delete'), icon: 'i-lucide-trash' },
];
</script>

<template>
  <div class="flex gap-1">
    <Button
      v-for="action in actions"
      :key="action.key"
      v-tooltip.top="labels[action.key]"
      v-bind="buttonProps"
      :icon="action.icon"
      :aria-label="labels[action.key]"
      :data-action="action.key"
      :disabled="action.key === 'edit' ? !canEdit : !canManage"
      :class="{ 'hover:enabled:text-n-ruby-11': action.key === 'delete' }"
      @click.stop="action.run()"
    />
  </div>
</template>
