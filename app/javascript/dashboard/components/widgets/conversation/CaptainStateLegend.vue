<script setup>
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { ref } from 'vue';

import NextButton from 'dashboard/components-next/button/Button.vue';

const isOpen = ref(false);
const ITEMS = [
  { key: 'ANSWERING', swatch: 'bg-n-teal-9' },
  { key: 'WAITING', swatch: 'bg-n-amber-9' },
  { key: 'ESCALATED', swatch: 'bg-n-ruby-9 animate-pulse' },
];
</script>

<template>
  <MenuPopover
    v-model:open="isOpen"
    :label="$t('CHAT_LIST.CAPTAIN_LEGEND.TITLE')"
    panel-class="w-64 max-w-[calc(100vw-2rem)]"
  >
    <template #trigger>
      <NextButton
        icon="i-lucide-info"
        slate
        ghost
        xs
        :aria-label="$t('CHAT_LIST.CAPTAIN_LEGEND.TITLE')"
        data-testid="captain-legend-toggle"
        @click="isOpen = !isOpen"
      />
    </template>
    <template #content>
      <div
        data-testid="captain-legend"
        class="flex flex-col gap-3 px-2 pb-2 overflow-y-auto min-h-0"
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
    </template>
  </MenuPopover>
</template>
