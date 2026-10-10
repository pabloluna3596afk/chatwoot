<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatTemplateDateTime } from 'dashboard/routes/dashboard/settings/templates/templateUtils';

// One refresh button and one "last time" line, shared by Plantillas, Flows and the send center,
// so the three views look and behave the same way. The caller decides what refreshing does.
const props = defineProps({
  label: { type: String, required: true },
  date: { type: [Date, String, Number], default: null },
  isLoading: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  buttonLabel: { type: String, required: true },
  // In narrow places (send center) show only the time when the date is today.
  short: { type: Boolean, default: false },
  buttonTestid: { type: String, default: 'sync-status-button' },
});
const emit = defineEmits(['refresh']);
const when = computed(() =>
  props.date ? formatTemplateDateTime(props.date, { short: props.short }) : ''
);
</script>

<template>
  <div class="flex items-center gap-2 min-w-0" data-testid="sync-status">
    <Button
      type="button"
      icon="i-lucide-refresh-cw"
      ghost
      slate
      sm
      :is-loading="isLoading"
      :disabled="disabled || isLoading"
      :aria-label="buttonLabel"
      :title="buttonLabel"
      :data-testid="buttonTestid"
      @click="emit('refresh')"
    />
    <span
      v-if="when"
      class="truncate text-xs text-n-slate-10"
      data-testid="sync-status-text"
    >
      {{ label.replace('{date}', when) }}
    </span>
  </div>
</template>
