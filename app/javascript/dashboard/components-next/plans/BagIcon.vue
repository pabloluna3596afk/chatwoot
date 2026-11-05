<script setup>
import { AI_BAG_ICONS } from './bagIcons';

defineProps({
  bag: { type: String, required: true },
});
</script>

<template>
  <span :class="AI_BAG_ICONS[bag]" aria-hidden="true" />
</template>
