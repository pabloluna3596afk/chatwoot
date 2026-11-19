<script setup>
import BaseBubble from './Base.vue';
import MediaGrid from '../media/MediaGrid.vue';
import { useMessageContext } from '../provider';
const { attachments, content } = useMessageContext();
</script>

<template>
  <BaseBubble
    overlay-meta
    class="overflow-hidden p-1 [&>button]:mx-0 [&>button]:w-auto"
    data-bubble-name="image"
  >
    <MediaGrid :items="attachments" :caption="content || ''" />
  </BaseBubble>
</template>
