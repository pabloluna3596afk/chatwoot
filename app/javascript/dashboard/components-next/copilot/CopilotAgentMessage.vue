<script setup>
defineProps({
  message: {
    type: Object,
    required: true,
  },
});
</script>

<template>
  <div class="space-y-1 text-inherit">
    <div class="break-words">
      {{ message.content }}
    </div>
  </div>
</template>
