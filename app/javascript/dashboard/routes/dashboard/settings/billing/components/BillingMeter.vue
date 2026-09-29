<script setup>
import { computed } from 'vue';
import { formatBytes } from 'shared/helpers/FileHelper';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  consumed: {
    type: Number,
    required: true,
  },
  totalCount: {
    type: Number,
    required: true,
  },
  // 'bytes' renders the values as KB/MB/GB instead of a bare number
  unit: {
    type: String,
    default: null,
  },
});

const displayConsumed = computed(() =>
  props.unit === 'bytes' ? formatBytes(props.consumed) : props.consumed
);

const displayTotal = computed(() =>
  props.unit === 'bytes' ? formatBytes(props.totalCount) : props.totalCount
);

const percent = computed(() =>
  Math.round((props.consumed / props.totalCount) * 100)
);

const colorClass = computed(() => {
  if (percent.value < 50) {
    return 'bg-n-teal-10';
  }
  if (percent.value < 80) {
    return 'bg-n-amber-10';
  }
  return 'bg-n-ruby-10';
});
</script>

<template>
  <div class="px-5">
    <div class="text-n-slate-11 text-xs">{{ title }}</div>
    <div class="mt-2 text-xs tabular-nums text-n-slate-10">
      {{ displayConsumed }} / {{ displayTotal }}
    </div>
    <div class="mt-2">
      <div class="rounded-full overflow-hidden h-2.5 w-full bg-n-slate-4">
        <div
          class="h-2.5"
          :class="colorClass"
          :style="{ width: `${percent}%` }"
        />
      </div>
    </div>
  </div>
</template>
