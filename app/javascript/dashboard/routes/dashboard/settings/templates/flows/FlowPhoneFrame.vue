<script setup>
defineProps({
  title: { type: String, required: true },
  screenIndex: { type: Number, required: true },
  screenCount: { type: Number, required: true },
});
</script>

<template>
  <div
    class="flex flex-col w-[22.5rem] h-[46.25rem] shrink-0 overflow-hidden border-8 border-slate-800 rounded-[2rem] bg-[#e8dfd2] dark:bg-[#1b2630]"
    data-testid="flow-phone-frame"
  >
    <div
      class="flex justify-between gap-2 px-4 py-2.5 text-sm font-semibold text-white bg-[#1f9d6a] shrink-0"
    >
      <span class="truncate">{{ title }}</span>
      <span class="shrink-0">{{ screenIndex + 1 }} / {{ screenCount }}</span>
    </div>
    <div
      class="flex flex-col flex-1 min-h-0 mt-8 overflow-y-auto overscroll-contain rounded-t-[1.1rem] bg-n-solid-1 text-n-slate-12"
      data-testid="flow-phone-scroll"
    >
      <slot />
    </div>
  </div>
</template>
