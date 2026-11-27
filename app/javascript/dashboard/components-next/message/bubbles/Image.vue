<script setup>
import BaseBubble from './Base.vue';
import MediaGrid from '../media/MediaGrid.vue';
import { useMessageContext } from '../provider';
import { computed } from 'vue';
const { attachments, content, contentType } = useMessageContext();
const isSticker = computed(() => contentType.value === 'sticker');
</script>

<template>
  <BaseBubble
    class="overflow-hidden"
    :content-class="
      isSticker
        ? 'p-0 [&_button]:mx-0 [&_button]:w-auto'
        : 'p-1 [&_button]:mx-0 [&_button]:w-auto'
    "
    data-bubble-name="image"
  >
    <MediaGrid :items="attachments" :caption="content || ''" />
  </BaseBubble>
</template>
