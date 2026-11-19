<script setup>
import FileCard from '../media/FileCard.vue';
defineProps({
  attachment: { type: Object, required: true },
  channelType: { type: String, default: '' },
});
</script>

<template>
  <FileCard :attachment="attachment" :channel-type="channelType" />
</template>
