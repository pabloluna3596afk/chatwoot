<script setup>
import { useI18n } from 'vue-i18n';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import PanelIaStateLegend from 'dashboard/components-next/PanelIa/PanelIaStateLegend.vue';

const { t } = useI18n();
</script>

<template>
  <Popover align="start" :show-content-border="false">
    <template #default="{ isOpen }">
      <button
        type="button"
        class="inline-flex items-center gap-1 p-0 text-xs transition-colors bg-transparent border-0 cursor-help"
        :class="
          isOpen ? 'text-n-slate-12' : 'text-n-slate-10 hover:text-n-slate-12'
        "
        :aria-label="t('AGENT_BOTS.LIST.STATE_LEGEND_HINT')"
      >
        <span class="i-lucide-info size-3.5" />
        {{ t('AGENT_BOTS.LIST.STATE_LEGEND_HINT') }}
      </button>
    </template>
    <template #content>
      <div class="w-80">
        <PanelIaStateLegend />
      </div>
    </template>
  </Popover>
</template>
