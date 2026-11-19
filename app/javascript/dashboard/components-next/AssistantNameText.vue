<script setup>
import { computed } from 'vue';
import {
  ASSISTANT_NAME_MARKER,
  truncateAssistantName,
} from 'dashboard/composables/useAssistantName';

const props = defineProps({ text: { type: String, required: true } });
defineOptions({ inheritAttrs: false });
const parts = computed(() => props.text.split(ASSISTANT_NAME_MARKER));
</script>

<template>
  <template v-for="(part, index) in parts" :key="index">
    <span v-if="index % 2" class="assistant-name" :title="part">{{
      truncateAssistantName(part)
    }}</span>
    <template v-else>{{ part }}</template>
  </template>
</template>

<style>
/* Style B (owner choice): brand-blue vertical gradient clipped to the text, weight 600.
   Both stops keep >= 4.5:1 contrast on the surface in each theme. */
.assistant-name {
  --assistant-name-top: #1073e9;
  --assistant-name-bottom: #0b3f8a;
  font-weight: 600;
  background-image: linear-gradient(
    180deg,
    var(--assistant-name-top),
    var(--assistant-name-bottom)
  );
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  -webkit-text-fill-color: transparent;
}

.dark .assistant-name {
  --assistant-name-top: #c2ddff;
  --assistant-name-bottom: #5fa2fb;
}

@media (forced-colors: active) {
  .assistant-name {
    background-image: none;
    color: LinkText;
    -webkit-text-fill-color: currentColor;
  }
}
</style>
