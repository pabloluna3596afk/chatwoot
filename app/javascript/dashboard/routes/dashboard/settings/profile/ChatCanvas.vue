<script setup>
import { useChatCanvas } from 'dashboard/composables/useChatCanvas';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

const { currentCanvasId, canvasOptions, updateChatCanvas } = useChatCanvas();
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3 w-full">
      <RadioCard
        v-for="option in canvasOptions"
        :id="option.id"
        :key="option.id"
        name="chat_canvas"
        :label="option.label"
        :description="option.description"
        :is-active="currentCanvasId === option.id"
        @select="updateChatCanvas"
      >
        <img
          :src="option.preview"
          alt=""
          class="mt-1 w-full h-16 rounded-lg border border-n-weak object-cover object-center"
        />
      </RadioCard>
    </div>
  </div>
</template>
