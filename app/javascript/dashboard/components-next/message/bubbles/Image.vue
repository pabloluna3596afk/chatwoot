<script setup>
import BaseBubble from './Base.vue';
import MediaGrid from '../media/MediaGrid.vue';
import { useMessageContext } from '../provider';
const { attachments, content } = useMessageContext();
</script>

<template>
  <BaseBubble
    class="overflow-hidden"
    content-class="p-1 [&_button]:mx-0 [&_button]:w-auto"
    data-bubble-name="image"
  >
    <MediaGrid :items="attachments" :caption="content || ''" />
  </BaseBubble>
</template>
