<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { tintStylesFromHex } from 'dashboard/helper/colorHelper';

const props = defineProps({
  color: { type: String, default: '#1f93ff' },
  label: { type: String, default: '' },
});

const { t } = useI18n();

const tintStyles = computed(() => tintStylesFromHex(props.color));
const displayLabel = computed(
  () => props.label?.trim() || t('GENERAL.COLOR_PREVIEW.SAMPLE')
);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="text-xs text-n-slate-11">
      {{ $t('GENERAL.COLOR_PREVIEW.TITLE') }}
    </span>
    <div class="flex flex-wrap items-center gap-3">
      <div
        class="inline-flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
      >
        <span class="text-[10px] text-n-slate-10 shrink-0">
          {{ $t('GENERAL.COLOR_PREVIEW.LIGHT') }}
        </span>
        <span
          class="inline-flex w-fit max-w-[12rem] items-center rounded-md border px-1.5 py-0.5 text-xs font-medium truncate"
          :style="tintStyles"
        >
          {{ displayLabel }}
        </span>
      </div>
      <div
        class="inline-flex items-center gap-2 rounded-lg border border-n-slate-6 bg-[rgb(28,32,36)] px-2.5 py-1.5"
      >
        <span class="text-[10px] text-[rgb(139,141,152)] shrink-0">
          {{ $t('GENERAL.COLOR_PREVIEW.DARK') }}
        </span>
        <span
          class="inline-flex w-fit max-w-[12rem] items-center rounded-md border px-1.5 py-0.5 text-xs font-medium truncate"
          :style="tintStyles"
        >
          {{ displayLabel }}
        </span>
      </div>
    </div>
  </div>
</template>
