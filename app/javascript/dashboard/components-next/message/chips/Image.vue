<script setup>
import MediaGrid from '../media/MediaGrid.vue';
defineProps({ attachment: { type: Object, required: true } });
</script>

<template>
  <MediaGrid :items="[attachment]" />
</template>
