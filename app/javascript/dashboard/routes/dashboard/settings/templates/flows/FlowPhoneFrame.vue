<script setup>
import { PHONE_PREVIEW_WIDTH } from 'dashboard/components-next/whatsapp/phonePreview';
defineProps({
  title: { type: String, required: true },
  screenIndex: { type: Number, required: true },
  screenCount: { type: Number, required: true },
});
</script>

<template>
  <div
    class="flex flex-col w-[min(100%,var(--phone-preview-width))] h-[clamp(24rem,calc(100dvh-15rem),38rem)] min-[1200px]:h-[clamp(24rem,calc(100dvh-12rem),42rem)] shrink-0 overflow-hidden border-8 border-slate-800 rounded-[2rem] bg-[#e8dfd2] dark:bg-[#1b2630]"
    :class="PHONE_PREVIEW_WIDTH"
    data-testid="flow-phone-frame"
  >
    <div
      class="flex justify-between gap-2 px-4 py-2.5 text-sm font-semibold text-white bg-[#1f9d6a] shrink-0"
    >
      <h3
        tabindex="-1"
        class="m-0 truncate text-sm font-semibold text-white outline-none"
        data-testid="flow-preview-heading"
      >
        {{ title }}
      </h3>
      <span class="shrink-0">{{ screenIndex + 1 }} / {{ screenCount }}</span>
    </div>
    <div
      class="flex flex-col flex-1 min-h-0 mt-4 overflow-y-auto overscroll-contain rounded-t-[1.1rem] bg-n-solid-1 text-n-slate-12"
      data-testid="flow-phone-scroll"
    >
      <slot />
    </div>
  </div>
</template>
