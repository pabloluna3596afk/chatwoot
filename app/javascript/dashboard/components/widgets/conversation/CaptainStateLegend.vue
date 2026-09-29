<script setup>
import { ref } from 'vue';
import { onClickOutside } from '@vueuse/core';
import NextButton from 'dashboard/components-next/button/Button.vue';

const isOpen = ref(false);
const root = ref(null);

onClickOutside(root, () => {
  isOpen.value = false;
});

const ITEMS = [
  { key: 'ANSWERING', swatch: 'bg-n-teal-9' },
  { key: 'WAITING', swatch: 'bg-n-amber-9' },
  { key: 'ESCALATED', swatch: 'bg-n-ruby-9 animate-pulse' },
];
</script>

<template>
  <div ref="root" class="relative flex items-center">
    <NextButton
      icon="i-lucide-info"
      slate
      ghost
      xs
      :aria-label="$t('CHAT_LIST.CAPTAIN_LEGEND.TITLE')"
      data-testid="captain-legend-toggle"
      @click="isOpen = !isOpen"
    />
    <div
      v-if="isOpen"
      class="absolute z-50 top-full mt-1 ltr:left-0 rtl:right-0 w-64 p-3 rounded-xl border border-n-slate-4 bg-n-slate-3 shadow-lg"
      data-testid="captain-legend"
    >
      <p class="m-0 mb-2 text-xs font-medium text-n-slate-12">
        {{ $t('CHAT_LIST.CAPTAIN_LEGEND.TITLE') }}
      </p>
      <ul class="m-0 p-0 list-none flex flex-col gap-1.5">
        <li
          v-for="item in ITEMS"
          :key="item.key"
          class="flex items-center gap-2 text-xs text-n-slate-11"
        >
          <span class="size-2.5 rounded-full shrink-0" :class="item.swatch" />
          {{ $t(`CHAT_LIST.CAPTAIN_LEGEND.${item.key}`) }}
        </li>
      </ul>
      <p class="m-0 mt-2 text-xs text-n-slate-10">
        {{ $t('CHAT_LIST.CAPTAIN_LEGEND.TAKEN') }}
      </p>
    </div>
  </div>
</template>
