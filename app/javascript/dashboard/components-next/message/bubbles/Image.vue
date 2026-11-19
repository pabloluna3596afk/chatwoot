<script setup>
import BaseBubble from './Base.vue';
import MediaGrid from '../media/MediaGrid.vue';
import { useMessageContext } from '../provider';
const { attachments, content } = useMessageContext();
</script>

<template>
  <BaseBubble class="overflow-hidden p-3" data-bubble-name="image">
    <MediaGrid :items="attachments" :caption="content || ''" />
  </BaseBubble>
</template>
