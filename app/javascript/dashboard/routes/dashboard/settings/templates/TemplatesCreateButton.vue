<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({ action: { type: Object, required: true } });
</script>

<template>
  <Button
    type="button"
    size="sm"
    icon="i-lucide-plus"
    :label="action.label"
    data-testid="page-create"
    @click="action.run"
  />
</template>
