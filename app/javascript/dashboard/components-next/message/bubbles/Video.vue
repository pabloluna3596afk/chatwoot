<script setup>
import BaseBubble from './Base.vue';
import MediaGrid from '../media/MediaGrid.vue';
import { useMessageContext } from '../provider';

const emit = defineEmits(['error']);
const { attachments, content } = useMessageContext();
</script>

<template>
  <BaseBubble overlay-meta class="overflow-hidden p-1" data-bubble-name="video">
    <MediaGrid
      :items="attachments"
      :caption="content || ''"
      @error="emit('error')"
    />
  </BaseBubble>
</template>
