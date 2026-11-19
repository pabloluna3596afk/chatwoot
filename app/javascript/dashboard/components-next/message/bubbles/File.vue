<script setup>
import { useMessageContext } from '../provider';
import BaseBubble from './Base.vue';
import FileCard from '../media/FileCard.vue';
const { attachments, channelType } = useMessageContext();
</script>

<template>
  <BaseBubble class="p-2" data-bubble-name="file">
    <FileCard :attachment="attachments[0]" :channel-type="channelType" />
  </BaseBubble>
</template>
