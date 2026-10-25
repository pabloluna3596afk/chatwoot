<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import PresetCard from 'dashboard/components-next/preset/PresetCard.vue';

defineProps({
  id: { type: [String, Number], required: true },
  title: { type: String, required: true },
  description: {
    type: String,
    default: '',
  },
  loading: {
    type: Boolean,
    default: false,
  },
  actionLabel: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['apply']);
</script>

<template>
  <PresetCard
    :id="id"
    :title="title"
    :description="description"
    :action-label="actionLabel"
    @apply="emit('apply', id)"
  >
    <template #actions>
      <Button
        sm
        faded
        icon="i-lucide-sparkles"
        :label="actionLabel"
        :is-loading="loading"
        :aria-label="`${actionLabel}: ${title}`"
        @click="emit('apply', id)"
      />
    </template>
    <template v-if="$slots.meta" #meta>
      <slot name="meta" />
    </template>
  </PresetCard>
</template>
